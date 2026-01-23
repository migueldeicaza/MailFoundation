//
// MessageSummary.swift
//
// Ported from MailKit (C#) to Swift.
//

import Foundation

public struct MessageSummary: Sendable, Equatable {
    public let sequence: Int
    public let uniqueId: UniqueId?
    public let flags: MessageFlags
    public let keywords: [String]
    public let internalDate: String?
    public let size: Int?
    public let modSeq: UInt64?
    public let envelope: ImapEnvelope?
    public let bodyStructure: ImapBodyStructure?
    public let body: ImapBodyStructure?
    public let headers: [String: String]
    public let references: MessageIdList?
    public let previewText: String?
    public let items: MessageSummaryItems

    public var index: Int {
        sequence > 0 ? sequence - 1 : 0
    }

    public init(
        sequence: Int,
        items: MessageSummaryItems = .none,
        uniqueId: UniqueId? = nil,
        flags: MessageFlags = [],
        keywords: [String] = [],
        internalDate: String? = nil,
        size: Int? = nil,
        modSeq: UInt64? = nil,
        envelope: ImapEnvelope? = nil,
        bodyStructure: ImapBodyStructure? = nil,
        body: ImapBodyStructure? = nil,
        headers: [String: String] = [:],
        references: MessageIdList? = nil,
        previewText: String? = nil
    ) {
        self.sequence = sequence
        self.uniqueId = uniqueId
        self.flags = flags
        self.keywords = keywords
        self.internalDate = internalDate
        self.size = size
        self.modSeq = modSeq
        self.envelope = envelope
        self.bodyStructure = bodyStructure
        self.body = body
        self.headers = headers
        self.references = references
        self.previewText = previewText
        self.items = items
    }

    public init?(fetch: ImapFetchResponse) {
        guard let summary = MessageSummary.build(fetch: fetch, bodyMap: nil) else { return nil }
        self = summary
    }

    public static func build(fetch: ImapFetchResponse, bodyMap: ImapFetchBodyMap?) -> MessageSummary? {
        guard let attributes = ImapFetchAttributes.parse(fetch) else { return nil }

        var items: MessageSummaryItems = []

        if !attributes.flags.isEmpty { items.insert(.flags) }
        if let uid = attributes.uid, uid > 0 { items.insert(.uniqueId) }
        if attributes.internalDate != nil { items.insert(.internalDate) }
        if attributes.size != nil { items.insert(.size) }
        if attributes.modSeq != nil { items.insert(.modSeq) }
        if attributes.envelopeRaw != nil { items.insert(.envelope) }
        if attributes.bodyStructure != nil { items.insert(.bodyStructure) }
        if attributes.body != nil { items.insert(.body) }

        let parsedFlags = MessageFlags.parse(attributes.flags)
        let uniqueId = attributes.uid.flatMap { $0 > 0 ? UniqueId(id: $0) : nil }

        var headers: [String: String] = [:]
        var references: MessageIdList?
        var previewText: String?

        if let bodyMap {
            if let headerBytes = headerPayload(from: bodyMap) {
                headers = HeaderFieldParser.parse(headerBytes)
                if !headers.isEmpty { items.insert(.headers) }
                if let value = headers["REFERENCES"], let parsed = MessageIdList.parse(value) {
                    references = parsed
                    items.insert(.references)
                } else if let value = headers["IN-REPLY-TO"], let parsed = MessageIdList.parse(value) {
                    references = parsed
                    items.insert(.references)
                }
            }
            if let previewBytes = previewPayload(from: bodyMap) {
                previewText = decodePreviewText(previewBytes)
                if let previewText, !previewText.isEmpty {
                    items.insert(.previewText)
                }
            }
        }

        return MessageSummary(
            sequence: fetch.sequence,
            items: items,
            uniqueId: uniqueId,
            flags: parsedFlags.flags,
            keywords: parsedFlags.keywords,
            internalDate: attributes.internalDate,
            size: attributes.size,
            modSeq: attributes.modSeq,
            envelope: attributes.parsedImapEnvelope(),
            bodyStructure: attributes.parsedBodyStructure(),
            body: attributes.body.flatMap(ImapBodyStructure.parse),
            headers: headers,
            references: references,
            previewText: previewText
        )
    }

    private static func headerPayload(from bodyMap: ImapFetchBodyMap) -> [UInt8]? {
        for payload in bodyMap.payloads {
            guard let subsection = payload.section?.subsection else { continue }
            switch subsection {
            case .header, .headerFields, .headerFieldsNot:
                return payload.data
            default:
                continue
            }
        }
        return nil
    }

    private static func previewPayload(from bodyMap: ImapFetchBodyMap) -> [UInt8]? {
        for payload in bodyMap.payloads {
            guard let subsection = payload.section?.subsection else { continue }
            if case .text = subsection {
                return payload.data
            }
        }

        if let full = bodyMap.payloads.first(where: { $0.section == nil })?.data {
            return stripHeaders(full)
        }

        return nil
    }

    private static func stripHeaders(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count < 4 { return bytes }
        for index in 0..<(bytes.count - 3) {
            if bytes[index] == 13,
               bytes[index + 1] == 10,
               bytes[index + 2] == 13,
               bytes[index + 3] == 10 {
                return Array(bytes[(index + 4)...])
            }
        }
        return bytes
    }

    private static func decodePreviewText(_ bytes: [UInt8]) -> String? {
        let data = Data(bytes)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let text else { return nil }
        let trimmed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 512 { return trimmed }
        return String(trimmed.prefix(512))
    }
}
