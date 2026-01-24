//
// ImapESearchResponse.swift
//
// IMAP ESEARCH response parsing helpers.
//

public struct ImapESearchResponse: Sendable, Equatable {
    public let ids: [UInt32]
    public let count: Int?
    public let min: UInt32?
    public let max: UInt32?
    public let isUid: Bool

    public static func parse(_ line: String) -> ImapESearchResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 9 else { return nil }
        let upper = trimmed.uppercased()
        guard upper.hasPrefix("* ESEARCH") else { return nil }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 9)
        let remainder = trimmed[startIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = tokenize(String(remainder))
        if tokens.isEmpty { return ImapESearchResponse(ids: [], count: nil, min: nil, max: nil, isUid: false) }

        var index = 0

        if index < tokens.count, tokens[index] == "(" {
            index += 1
            while index < tokens.count, tokens[index] != ")" {
                index += 1
            }
            if index < tokens.count, tokens[index] == ")" {
                index += 1
            }
        }

        var isUid = false
        if index < tokens.count, tokens[index].caseInsensitiveEquals("UID") {
            isUid = true
            index += 1
        }

        var ids: [UInt32] = []
        var count: Int?
        var minValue: UInt32?
        var maxValue: UInt32?

        while index < tokens.count {
            let key = tokens[index].uppercased()
            index += 1
            guard index < tokens.count else { break }
            let value = tokens[index]
            index += 1

            switch key {
            case "ALL":
                if let set = SequenceSet.tryParse(value) {
                    ids = Array(set)
                }
            case "COUNT":
                if let parsed = Int(value) {
                    count = parsed
                }
            case "MIN":
                if let parsed = UInt32(value) {
                    minValue = parsed
                }
            case "MAX":
                if let parsed = UInt32(value) {
                    maxValue = parsed
                }
            default:
                continue
            }
        }

        return ImapESearchResponse(ids: ids, count: count, min: minValue, max: maxValue, isUid: isUid)
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
            if ch == "(" || ch == ")" {
                tokens.append(String(ch))
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
                if current.isWhitespace || current == "(" || current == ")" {
                    break
                }
                index = text.index(after: index)
            }
            tokens.append(String(text[start..<index]))
        }

        return tokens
    }
}

private extension String {
    func caseInsensitiveEquals(_ other: String) -> Bool {
        compare(other, options: [.caseInsensitive]) == .orderedSame
    }
}
