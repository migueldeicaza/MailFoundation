//
// ImapNamespaceResponse.swift
//
// IMAP NAMESPACE response parsing.
//

import Foundation

public struct ImapNamespaceEntry: Sendable, Equatable {
    public let prefix: String?
    public let delimiter: String?

    public init(prefix: String?, delimiter: String?) {
        self.prefix = prefix
        self.delimiter = delimiter
    }
}

public struct ImapNamespaceResponse: Sendable, Equatable {
    public let personal: [ImapNamespaceEntry]
    public let otherUsers: [ImapNamespaceEntry]
    public let shared: [ImapNamespaceEntry]

    public static func parse(_ line: String) -> ImapNamespaceResponse? {
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

        func consumeNamespaceEntryTail() -> Bool {
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
                        if depth == 0 {
                            index = trimmed.index(after: index)
                            return true
                        }
                        depth -= 1
                    }
                }
                index = trimmed.index(after: index)
            }
            return false
        }

        func readNamespaceEntry() -> ImapNamespaceEntry? {
            skipWhitespace()
            guard index < trimmed.endIndex, trimmed[index] == "(" else { return nil }
            index = trimmed.index(after: index)
            guard let prefixValue = readStringOrNil() else { return nil }
            guard let delimiterValue = readStringOrNil() else { return nil }
            skipWhitespace()
            guard consumeNamespaceEntryTail() else { return nil }
            return ImapNamespaceEntry(prefix: prefixValue, delimiter: delimiterValue)
        }

        func readNamespaceList() -> [ImapNamespaceEntry]? {
            skipWhitespace()
            guard index < trimmed.endIndex else { return nil }
            if trimmed[index] != "(" {
                guard let atom = readAtom(), atom.uppercased() == "NIL" else { return nil }
                return []
            }
            index = trimmed.index(after: index)
            var entries: [ImapNamespaceEntry] = []
            while index < trimmed.endIndex {
                skipWhitespace()
                if index < trimmed.endIndex, trimmed[index] == ")" {
                    index = trimmed.index(after: index)
                    return entries
                }
                guard let entry = readNamespaceEntry() else { return nil }
                entries.append(entry)
            }
            return nil
        }

        guard let command = readAtom(), command.uppercased() == "NAMESPACE" else { return nil }
        guard let personal = readNamespaceList() else { return nil }
        guard let otherUsers = readNamespaceList() else { return nil }
        guard let shared = readNamespaceList() else { return nil }
        return ImapNamespaceResponse(personal: personal, otherUsers: otherUsers, shared: shared)
    }
}
