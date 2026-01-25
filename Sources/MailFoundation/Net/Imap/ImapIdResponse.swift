//
// ImapIdResponse.swift
//
// IMAP ID response parsing.
//

import Foundation

public struct ImapIdResponse: Sendable, Equatable {
    public let values: [String: String?]

    public static func parse(_ line: String) -> ImapIdResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("* ID") else { return nil }

        let remainder = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.uppercased().hasPrefix("NIL") {
            return ImapIdResponse(values: [:])
        }
        guard remainder.first == "(" else { return nil }
        guard let end = remainder.lastIndex(of: ")") else { return nil }
        let inner = remainder[remainder.index(after: remainder.startIndex)..<end]
        let tokens = tokenize(String(inner))
        guard !tokens.isEmpty else { return ImapIdResponse(values: [:]) }

        var values: [String: String?] = [:]
        var index = 0
        while index + 1 < tokens.count {
            let key = tokens[index]
            let rawValue = tokens[index + 1]
            let value = rawValue.caseInsensitiveCompare("NIL") == .orderedSame ? nil : rawValue
            values[key] = value
            index += 2
        }
        return ImapIdResponse(values: values)
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            if ch.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if ch == "\"" {
                index = text.index(after: index)
                var value = ""
                while index < text.endIndex {
                    let current = text[index]
                    if current == "\\" {
                        let next = text.index(after: index)
                        if next < text.endIndex {
                            value.append(text[next])
                            index = text.index(after: next)
                        } else {
                            index = next
                        }
                        continue
                    }
                    if current == "\"" {
                        index = text.index(after: index)
                        break
                    }
                    value.append(current)
                    index = text.index(after: index)
                }
                tokens.append(value)
                continue
            }

            let start = index
            while index < text.endIndex {
                let current = text[index]
                if current.isWhitespace {
                    break
                }
                index = text.index(after: index)
            }
            tokens.append(String(text[start..<index]))
        }

        return tokens
    }
}
