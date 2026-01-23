//
// ImapFetchAttributes.swift
//
// Parse common IMAP FETCH attributes from a FETCH response payload.
//

import Foundation

public struct ImapFetchAttributes: Sendable, Equatable {
    public let flags: [String]
    public let uid: UInt32?
    public let size: Int?
    public let internalDate: String?
    public let modSeq: UInt64?
    public let envelopeRaw: String?
    public let bodyStructure: String?
    public let body: String?

    public init(
        flags: [String] = [],
        uid: UInt32? = nil,
        size: Int? = nil,
        internalDate: String? = nil,
        modSeq: UInt64? = nil,
        envelopeRaw: String? = nil,
        bodyStructure: String? = nil,
        body: String? = nil
    ) {
        self.flags = flags
        self.uid = uid
        self.size = size
        self.internalDate = internalDate
        self.modSeq = modSeq
        self.envelopeRaw = envelopeRaw
        self.bodyStructure = bodyStructure
        self.body = body
    }

    public static func parse(_ fetch: ImapFetchResponse) -> ImapFetchAttributes? {
        parsePayload(fetch.payload)
    }

    public static func parsePayload(_ payload: String) -> ImapFetchAttributes? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else {
            return nil
        }

        let contentStart = trimmed.index(after: trimmed.startIndex)
        let contentEnd = trimmed.index(before: trimmed.endIndex)
        let content = String(trimmed[contentStart..<contentEnd])
        let attributes = parseAttributes(content)

        let flags = parseFlags(attributes["FLAGS"])
        let uid = parseUInt32(attributes["UID"])
        let size = parseInt(attributes["RFC822.SIZE"])
        let internalDate = attributes["INTERNALDATE"]
        let modSeq = parseUInt64(attributes["MODSEQ"])
        let envelopeRaw = attributes["ENVELOPE"]
        let bodyStructure = attributes["BODYSTRUCTURE"]
        let body = attributes["BODY"]

        return ImapFetchAttributes(
            flags: flags,
            uid: uid,
            size: size,
            internalDate: internalDate,
            modSeq: modSeq,
            envelopeRaw: envelopeRaw,
            bodyStructure: bodyStructure,
            body: body
        )
    }

    public func parsedEnvelope() -> Envelope? {
        guard let envelopeRaw else { return nil }
        return Envelope.tryParse(envelopeRaw)
    }

    public func parsedImapEnvelope() -> ImapEnvelope? {
        guard let envelopeRaw else { return nil }
        return ImapEnvelope.parse(envelopeRaw)
    }

    public func parsedImapEnvelope(using cache: ImapEnvelopeCache) async -> ImapEnvelope? {
        guard let envelopeRaw else { return nil }
        return await cache.envelope(for: envelopeRaw)
    }

    public func parsedBodyStructure() -> ImapBodyStructure? {
        guard let bodyStructure else { return nil }
        return ImapBodyStructure.parse(bodyStructure)
    }

    private static func parseAttributes(_ content: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = content.startIndex

        func skipWhitespace() {
            while index < content.endIndex, content[index].isWhitespace {
                index = content.index(after: index)
            }
        }

        func readAtom() -> String? {
            skipWhitespace()
            guard index < content.endIndex else { return nil }
            let start = index
            while index < content.endIndex {
                let ch = content[index]
                if ch.isWhitespace || ch == "(" || ch == ")" || ch == "\"" {
                    break
                }
                index = content.index(after: index)
            }
            guard start < index else { return nil }
            return String(content[start..<index])
        }

        func readQuoted() -> String? {
            guard index < content.endIndex, content[index] == "\"" else { return nil }
            index = content.index(after: index)
            var result = ""
            var escape = false
            while index < content.endIndex {
                let ch = content[index]
                if escape {
                    result.append(ch)
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    index = content.index(after: index)
                    return result
                } else {
                    result.append(ch)
                }
                index = content.index(after: index)
            }
            return nil
        }

        func readParenthesized() -> String? {
            guard index < content.endIndex, content[index] == "(" else { return nil }
            var depth = 0
            var inQuote = false
            var escape = false
            let start = index
            while index < content.endIndex {
                let ch = content[index]
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
                            let end = content.index(after: index)
                            index = end
                            return String(content[start..<end])
                        }
                    }
                }
                index = content.index(after: index)
            }
            return nil
        }

        func readValue() -> String? {
            skipWhitespace()
            guard index < content.endIndex else { return nil }
            let ch = content[index]
            if ch == "\"" {
                return readQuoted()
            }
            if ch == "(" {
                return readParenthesized()
            }
            return readAtom()
        }

        while let name = readAtom() {
            let value = readValue()
            if let value {
                attributes[name.uppercased()] = value
            }
        }

        return attributes
    }

    private static func parseFlags(_ value: String?) -> [String] {
        guard let value else { return [] }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return [] }
        let start = trimmed.index(after: trimmed.startIndex)
        let end = trimmed.index(before: trimmed.endIndex)
        let inner = trimmed[start..<end]
        return inner.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    private static func parseInt(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value)
    }

    private static func parseUInt32(_ value: String?) -> UInt32? {
        guard let value else { return nil }
        return UInt32(value)
    }

    private static func parseUInt64(_ value: String?) -> UInt64? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
            trimmed.removeFirst()
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return UInt64(trimmed)
    }
}
