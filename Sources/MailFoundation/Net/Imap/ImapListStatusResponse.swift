//
// ImapListStatusResponse.swift
//
// IMAP LIST-STATUS response parsing.
//

import Foundation

public struct ImapListStatusResponse: Sendable, Equatable {
    public let mailbox: ImapMailbox
    public let statusItems: [String: Int]

    public static func parse(_ line: String) -> ImapListStatusResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") else { return nil }
        var index = trimmed.index(after: trimmed.startIndex)

        func skipWhitespace() {
            while index < trimmed.endIndex, trimmed[index].isWhitespace {
                index = trimmed.index(after: index)
            }
        }

        func readAtom() -> String? {
            skipWhitespace()
            guard index < trimmed.endIndex else { return nil }
            let start = index
            while index < trimmed.endIndex {
                let ch = trimmed[index]
                if ch.isWhitespace || ch == "(" || ch == ")" {
                    break
                }
                index = trimmed.index(after: index)
            }
            guard start < index else { return nil }
            return String(trimmed[start..<index])
        }

        func readQuoted() -> String? {
            guard index < trimmed.endIndex, trimmed[index] == "\"" else { return nil }
            index = trimmed.index(after: index)
            var result = ""
            var escape = false
            while index < trimmed.endIndex {
                let ch = trimmed[index]
                if escape {
                    result.append(ch)
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    index = trimmed.index(after: index)
                    return result
                } else {
                    result.append(ch)
                }
                index = trimmed.index(after: index)
            }
            return nil
        }

        func readStringOrNil() -> String?? {
            skipWhitespace()
            guard index < trimmed.endIndex else { return nil }
            if trimmed[index] == "\"" {
                if let value = readQuoted() {
                    return .some(value)
                }
                return nil
            }
            guard let atom = readAtom() else { return nil }
            if atom.uppercased() == "NIL" {
                return .some(nil)
            }
            return .some(atom)
        }

        func readAttributes() -> [String]? {
            skipWhitespace()
            guard index < trimmed.endIndex, trimmed[index] == "(" else { return nil }
            index = trimmed.index(after: index)
            var result: [String] = []
            while index < trimmed.endIndex {
                skipWhitespace()
                if index < trimmed.endIndex, trimmed[index] == ")" {
                    index = trimmed.index(after: index)
                    return result
                }
                if let value = readAtom() {
                    result.append(value)
                    continue
                }
                if let quoted = readQuoted() {
                    result.append(quoted)
                    continue
                }
                return nil
            }
            return nil
        }

        guard let command = readAtom(), command.uppercased() == "LIST" else {
            return nil
        }
        guard let attributes = readAttributes() else { return nil }
        guard let delimiterValue = readStringOrNil() else { return nil }
        guard let mailboxValue = readStringOrNil() else { return nil }
        guard let mailboxName = mailboxValue else { return nil }

        let mailbox = ImapMailbox(kind: .list, name: mailboxName, delimiter: delimiterValue, attributes: attributes)

        skipWhitespace()
        guard index < trimmed.endIndex, trimmed[index] == "(" else { return nil }
        let statusStart = index
        var depth = 0
        var inQuote = false
        var escape = false
        while index < trimmed.endIndex {
            let ch = trimmed[index]
            if inQuote {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inQuote = false
                }
            } else {
                if ch == "\"" {
                    inQuote = true
                } else if ch == "(" {
                    depth += 1
                } else if ch == ")" {
                    depth -= 1
                    if depth == 0 {
                        let end = trimmed.index(after: index)
                        let statusText = trimmed[statusStart..<end]
                        let statusItems = parseStatusItems(String(statusText))
                        return ImapListStatusResponse(mailbox: mailbox, statusItems: statusItems)
                    }
                }
            }
            index = trimmed.index(after: index)
        }
        return nil
    }

    private static func parseStatusItems(_ text: String) -> [String: Int] {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        var items: [String: Int] = [:]
        var idx = 0
        while idx + 1 < tokens.count {
            let key = tokens[idx].uppercased()
            let value = Int(tokens[idx + 1]) ?? 0
            items[key] = value
            idx += 2
        }
        return items
    }
}
