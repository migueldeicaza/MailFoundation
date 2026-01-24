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
    public let headerFetchKind: HeaderFetchKind?
    public let references: MessageIdList?
    public let previewText: String?
    public let items: MessageSummaryItems

    public var index: Int {
        sequence > 0 ? sequence - 1 : 0
    }

    public var normalizedSubject: String {
        ThreadableSubject.parse(envelope?.subject).normalized
    }

    public var isReply: Bool {
        ThreadableSubject.parse(envelope?.subject).replyDepth != 0
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
        headerFetchKind: HeaderFetchKind? = nil,
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
        self.headerFetchKind = headerFetchKind
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
        let bodyStructure = attributes.parsedBodyStructure()

        var headers: [String: String] = [:]
        var headerFetchKind: HeaderFetchKind?
        var references: MessageIdList?
        var previewText: String?

        if let bodyMap {
            if let headerPayload = headerPayload(from: bodyMap) {
                headers = HeaderFieldParser.parse(headerPayload.data)
                headerFetchKind = makeHeaderFetchKind(from: headerPayload)
                if !headers.isEmpty { items.insert(.headers) }
                if let value = headers["REFERENCES"], let parsed = MessageIdList.parse(value) {
                    references = parsed
                    items.insert(.references)
                } else if let value = headers["IN-REPLY-TO"], let parsed = MessageIdList.parse(value) {
                    references = parsed
                    items.insert(.references)
                }
            }
            if let previewPayload = previewPayload(from: bodyMap, bodyStructure: bodyStructure) {
                let contentType = previewContentType(for: previewPayload, bodyStructure: bodyStructure, headers: headers)
                previewText = decodePreviewText(previewPayload.data, contentType: contentType)
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
            bodyStructure: bodyStructure,
            body: attributes.body.flatMap(ImapBodyStructure.parse),
            headers: headers,
            headerFetchKind: headerFetchKind,
            references: references,
            previewText: previewText
        )
    }

    private static func headerPayload(from bodyMap: ImapFetchBodyMap) -> ImapFetchBodySectionPayload? {
        for payload in bodyMap.payloads {
            guard let subsection = payload.section?.subsection else { continue }
            switch subsection {
            case .header, .headerFields, .headerFieldsNot:
                return payload
            default:
                continue
            }
        }
        return nil
    }

    private static func previewPayload(
        from bodyMap: ImapFetchBodyMap,
        bodyStructure: ImapBodyStructure?
    ) -> ImapFetchBodySectionPayload? {
        let textPayloads = bodyMap.payloads.filter { payload in
            if let subsection = payload.section?.subsection, case .text = subsection {
                return true
            }
            return false
        }

        if !textPayloads.isEmpty {
            if let bodyStructure {
                let scored = textPayloads.map { payload -> (score: Int, payload: ImapFetchBodySectionPayload) in
                    let contentType = bodyStructure.resolve(section: payload.section ?? ImapFetchBodySection())?.contentType?.lowercased() ?? ""
                    let score: Int
                    if contentType.contains("text/plain") {
                        score = 0
                    } else if contentType.contains("text/html") {
                        score = 1
                    } else {
                        score = 2
                    }
                    return (score, payload)
                }
                if let best = scored.sorted(by: { $0.score < $1.score }).first {
                    return best.payload
                }
            }
            return textPayloads.first
        }

        if let full = bodyMap.payloads.first(where: { $0.section == nil })?.data {
            return ImapFetchBodySectionPayload(section: nil, peek: false, partial: nil, data: stripHeaders(full))
        }

        return nil
    }

    private static func makeHeaderFetchKind(from payload: ImapFetchBodySectionPayload) -> HeaderFetchKind? {
        guard let subsection = payload.section?.subsection else { return nil }
        switch subsection {
        case .header:
            return .all
        case .headerFields(let fields):
            return .fields(fields)
        case .headerFieldsNot(let fields):
            return .fieldsNot(fields)
        default:
            return nil
        }
    }

    private static func previewContentType(
        for payload: ImapFetchBodySectionPayload,
        bodyStructure: ImapBodyStructure?,
        headers: [String: String]
    ) -> String? {
        if let section = payload.section, let bodyStructure {
            return bodyStructure.resolve(section: section)?.contentType
        }
        if let headerValue = headers["CONTENT-TYPE"] {
            return headerValue
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

    private static func decodePreviewText(_ bytes: [UInt8], contentType: String?) -> String? {
        let data = Data(bytes)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let text else { return nil }

        let lowered = contentType?.lowercased() ?? ""
        let normalized = lowered.contains("text/html") ? htmlToText(text) : text
        let trimmed = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 512 { return trimmed }
        return String(trimmed.prefix(512))
    }

    private static func htmlToText(_ html: String) -> String {
        let withoutScript = html.replacingOccurrences(
            of: "<script[\\s\\S]*?</script>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutStyle = withoutScript.replacingOccurrences(
            of: "<style[\\s\\S]*?</style>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutTags = withoutStyle.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return decodeHtmlEntities(withoutTags)
    }

    private static func decodeHtmlEntities(_ text: String) -> String {
        var result = text
        let replacements: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, value) in replacements {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}

public enum HeaderFetchKind: Sendable, Equatable {
    case all
    case fields([String])
    case fieldsNot([String])
}
