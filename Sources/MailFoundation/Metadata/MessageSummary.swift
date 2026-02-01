//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

//
// MessageSummary.swift
//
// Ported from MailKit (C#) to Swift.
//

import Foundation
import MimeFoundation

/// A summary of a message containing metadata fetched from a mail server.
///
/// The `MessageSummary` structure contains information about a message that was fetched
/// from a mail folder. The properties that will be available depend on the
/// ``MessageSummaryItems`` flags passed to the fetch request.
///
/// This is the Swift equivalent of MailKit's `IMessageSummary` interface. It provides
/// access to message metadata such as flags, envelope information, body structure,
/// and other attributes without requiring the full message to be downloaded.
///
/// ## Topics
///
/// ### Message Identification
/// - ``sequence``
/// - ``uniqueId``
/// - ``index``
///
/// ### Message State
/// - ``flags``
/// - ``keywords``
///
/// ### Message Metadata
/// - ``internalDate``
/// - ``size``
/// - ``modSeq``
///
/// ### Envelope Information
/// - ``envelope``
/// - ``normalizedSubject``
/// - ``isReply``
///
/// ### Body Information
/// - ``bodyStructure``
/// - ``body``
/// - ``previewText``
///
/// ### Headers
/// - ``headers``
/// - ``headerFetchKind``
/// - ``references``
///
/// ## Example
///
/// ```swift
/// // Build a message summary from an IMAP FETCH response
/// if let summary = MessageSummary(fetch: fetchResponse) {
///     print("Subject: \(summary.envelope?.subject ?? "No subject")")
///     print("Flags: \(summary.flags)")
///     if summary.flags.contains(.seen) {
///         print("Message has been read")
///     }
/// }
/// ```
public struct MessageSummary: Sendable, Equatable {
    /// The message sequence number.
    ///
    /// The sequence number is the position of the message in the mailbox at the time
    /// of the fetch operation. Sequence numbers start at 1 and may change as messages
    /// are added or removed from the mailbox.
    ///
    /// For a stable identifier, use ``uniqueId`` instead.
    public let sequence: Int

    /// The unique identifier of the message, if available.
    ///
    /// The unique identifier (UID) is a stable identifier for a message within a mailbox
    /// that does not change unless the mailbox's UIDVALIDITY value changes.
    ///
    /// This property will only be set if the ``MessageSummaryItems/uniqueId`` flag
    /// was passed to the fetch request.
    public let uniqueId: UniqueId?

    /// The message flags.
    ///
    /// The standard IMAP message flags indicating the state of the message, such as
    /// whether it has been read, answered, flagged, or deleted.
    ///
    /// This property will only be set if the ``MessageSummaryItems/flags`` flag
    /// was passed to the fetch request.
    public let flags: MessageFlags

    /// The user-defined message keywords.
    ///
    /// User-defined flags or keywords that have been applied to the message.
    /// These are non-standard flags that extend beyond the basic IMAP flag set.
    ///
    /// This property will only be set if the ``MessageSummaryItems/flags`` flag
    /// was passed to the fetch request.
    public let keywords: [String]

    /// The internal date of the message, if available.
    ///
    /// The internal date is the date and time that the message was received by the
    /// server, often the same as found in the `Received` header.
    ///
    /// This property will only be set if the ``MessageSummaryItems/internalDate`` flag
    /// was passed to the fetch request.
    public let internalDate: String?

    /// The size of the message in bytes, if available.
    ///
    /// The RFC 822 size of the message as stored on the server.
    ///
    /// This property will only be set if the ``MessageSummaryItems/size`` flag
    /// was passed to the fetch request.
    public let size: Int?

    /// The mod-sequence value for the message, if available.
    ///
    /// The modification sequence number is used to track changes to the message
    /// and is part of the CONDSTORE extension (RFC 7162).
    ///
    /// This property will only be set if the ``MessageSummaryItems/modSeq`` flag
    /// was passed to the fetch request.
    public let modSeq: UInt64?

    /// The envelope of the message, if available.
    ///
    /// The envelope contains information such as the date the message was sent,
    /// the subject of the message, the sender, recipients, and the message-id.
    ///
    /// This property will only be set if the ``MessageSummaryItems/envelope`` flag
    /// was passed to the fetch request.
    public let envelope: ImapEnvelope?

    /// The full body structure of the message, if available.
    ///
    /// The body structure provides detailed information about the MIME structure
    /// of the message, including content types, encodings, and sizes of each part.
    ///
    /// This property will only be set if the ``MessageSummaryItems/bodyStructure`` flag
    /// was passed to the fetch request.
    public let bodyStructure: ImapBodyStructure?

    /// The basic body structure of the message, if available.
    ///
    /// A simplified version of the body structure without extension data.
    ///
    /// This property will only be set if the ``MessageSummaryItems/body`` flag
    /// was passed to the fetch request.
    public let body: ImapBodyStructure?

    /// The message headers, if available.
    ///
    /// A dictionary of header field names (uppercased) to their values.
    ///
    /// This property will only be set if the ``MessageSummaryItems/headers`` flag
    /// was passed to the fetch request, or if specific headers were requested.
    public let headers: [String: String]

    /// The kind of header fetch that was performed, if any.
    ///
    /// Indicates whether all headers were fetched, or only specific fields
    /// or all fields except certain ones.
    public let headerFetchKind: HeaderFetchKind?

    /// The message-ids that the message references, if available.
    ///
    /// Contains the message identifiers from the `References` or `In-Reply-To`
    /// headers, used for message threading.
    ///
    /// This property will only be set if the ``MessageSummaryItems/references`` flag
    /// was passed to the fetch request.
    public let references: MessageIdList?

    /// The preview text of the message, if available.
    ///
    /// A short snippet of the beginning of the message text, typically used
    /// in message lists to provide users with a sense of what the message is about.
    ///
    /// This property will only be set if the ``MessageSummaryItems/previewText`` flag
    /// was passed to the fetch request.
    public let previewText: String?

    /// A bitmask of fields that have been populated.
    ///
    /// Indicates which properties of the message summary contain valid data
    /// based on what was requested and returned from the server.
    public let items: MessageSummaryItems

    /// The zero-based index of the message.
    ///
    /// This is the message sequence number minus one, providing a zero-based
    /// index suitable for array access.
    public var index: Int {
        sequence > 0 ? sequence - 1 : 0
    }

    /// The normalized subject.
    ///
    /// A normalized `Subject` header value where prefixes such as `"Re:"`, `"Re[#]:"`,
    /// and `"FWD:"` have been pruned. This property is typically used for threading
    /// messages by subject.
    public var normalizedSubject: String {
        ThreadableSubject.parse(envelope?.subject).normalized
    }

    /// Whether the message is a reply.
    ///
    /// Returns `true` if the message subject contained any `"Re:"`, `"Re[#]:"`, or
    /// `"FWD:"` prefixes, indicating that the message is a reply or forward.
    public var isReply: Bool {
        ThreadableSubject.parse(envelope?.subject).replyDepth != 0
    }

    /// Creates a new message summary with the specified properties.
    ///
    /// - Parameters:
    ///   - sequence: The message sequence number.
    ///   - items: A bitmask of fields that have been populated.
    ///   - uniqueId: The unique identifier of the message.
    ///   - flags: The message flags.
    ///   - keywords: The user-defined message keywords.
    ///   - internalDate: The internal date of the message.
    ///   - size: The size of the message in bytes.
    ///   - modSeq: The mod-sequence value for the message.
    ///   - envelope: The envelope of the message.
    ///   - bodyStructure: The full body structure of the message.
    ///   - body: The basic body structure of the message.
    ///   - headers: The message headers.
    ///   - headerFetchKind: The kind of header fetch that was performed.
    ///   - references: The message-ids that the message references.
    ///   - previewText: The preview text of the message.
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

    /// Creates a message summary from an IMAP FETCH response.
    ///
    /// This initializer parses the FETCH response and extracts all available
    /// message attributes.
    ///
    /// - Parameter fetch: The IMAP FETCH response to parse.
    /// - Returns: A new message summary, or `nil` if the response cannot be parsed.
    public init?(fetch: ImapFetchResponse) {
        guard let summary = MessageSummary.build(fetch: fetch, bodyMap: nil) else { return nil }
        self = summary
    }

    /// Creates a message summary from an IMAP literal message.
    ///
    /// This initializer parses the FETCH response and extracts all available
    /// message attributes, including literal-based values when present.
    ///
    /// - Parameter message: The IMAP literal message to parse.
    /// - Returns: A new message summary, or `nil` if the response cannot be parsed.
    public init?(message: ImapLiteralMessage) {
        guard let summary = MessageSummary.build(message: message, bodyMap: nil) else { return nil }
        self = summary
    }

    /// Builds a message summary from an IMAP FETCH response with optional body data.
    ///
    /// This method parses the FETCH response and extracts all available message
    /// attributes, optionally using the body map to extract headers, references,
    /// and preview text.
    ///
    /// - Parameters:
    ///   - fetch: The IMAP FETCH response to parse.
    ///   - bodyMap: An optional map of body section payloads for extracting additional data.
    /// - Returns: A new message summary, or `nil` if the response cannot be parsed.
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
                previewText = decodePreviewText(
                    previewPayload.data,
                    payload: previewPayload,
                    bodyStructure: bodyStructure,
                    headers: headers
                )
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

    /// Builds a message summary from an IMAP literal message with optional body data.
    ///
    /// This method parses the FETCH response and extracts all available message
    /// attributes, optionally using the body map to extract headers, references,
    /// and preview text. Literal values are substituted when available.
    ///
    /// - Parameters:
    ///   - message: The IMAP literal message to parse.
    ///   - bodyMap: An optional map of body section payloads for extracting additional data.
    /// - Returns: A new message summary, or `nil` if the response cannot be parsed.
    public static func build(message: ImapLiteralMessage, bodyMap: ImapFetchBodyMap?) -> MessageSummary? {
        guard let fetch = ImapFetchResponse.parse(message.line) else { return nil }
        guard let attributes = ImapFetchAttributes.parse(message) else { return nil }

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
                previewText = decodePreviewText(
                    previewPayload.data,
                    payload: previewPayload,
                    bodyStructure: bodyStructure,
                    headers: headers
                )
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

    private static func decodePreviewText(
        _ bytes: [UInt8],
        payload: ImapFetchBodySectionPayload,
        bodyStructure: ImapBodyStructure?,
        headers: [String: String]
    ) -> String? {
        let context = previewContext(for: payload, bodyStructure: bodyStructure, headers: headers)
        let decodedBytes = decodeContentBytes(bytes, encoding: context.transferEncoding)
        guard let text = decodeText(decodedBytes, encoding: context.charsetEncoding) else { return nil }
        let previewer: TextPreviewer = context.format == .html ? HtmlTextPreviewer() : PlainTextPreviewer()
        let preview = previewer.getPreviewText(text)
        return preview.isEmpty ? nil : preview
    }

    private struct PreviewContext {
        let format: TextFormat
        let charsetEncoding: String.Encoding?
        let transferEncoding: ContentEncoding
    }

    private static func previewContext(
        for payload: ImapFetchBodySectionPayload,
        bodyStructure: ImapBodyStructure?,
        headers: [String: String]
    ) -> PreviewContext {
        var format: TextFormat = .plain
        var charset: String?
        var transferEncoding: ContentEncoding = .default

        if let section = payload.section,
           let bodyStructure,
           let resolution = bodyStructure.resolve(section: section),
           case let .single(part) = resolution.scope.node {
            charset = part.parameters["CHARSET"]
            if part.type.uppercased() == "TEXT", part.subtype.uppercased() == "HTML" {
                format = .html
            }
            if let encoding = part.encoding {
                transferEncoding = parseContentEncoding(encoding)
            }
        }

        var parsedContentType: ContentType?
        if let headerValue = headerValue(headers, name: "Content-Type"),
           let parsed = try? ContentType(parsing: headerValue) {
            parsedContentType = parsed
            if charset == nil {
                charset = parsed.charset
            }
            if format == .plain, parsed.isMimeType("text", "html") {
                format = .html
            }
        }

        if transferEncoding == .default,
           let encodingHeader = headerValue(headers, name: "Content-Transfer-Encoding") {
            transferEncoding = parseContentEncoding(encodingHeader)
        }

        let charsetEncoding = charset.flatMap { CharsetUtils.getEncoding($0) }
            ?? parsedContentType?.charsetEncoding

        return PreviewContext(format: format, charsetEncoding: charsetEncoding, transferEncoding: transferEncoding)
    }

    private static func parseContentEncoding(_ value: String?) -> ContentEncoding {
        guard let value else { return .default }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "7bit", "7-bit":
            return .sevenBit
        case "8bit", "8-bit":
            return .eightBit
        case "binary":
            return .binary
        case "base64":
            return .base64
        case "quoted-printable", "quotedprintable":
            return .quotedPrintable
        case "uuencode", "x-uuencode", "uuencoded", "x-uue":
            return .uuEncode
        default:
            return .default
        }
    }

    private static func decodeContentBytes(_ bytes: [UInt8], encoding: ContentEncoding) -> [UInt8] {
        switch encoding {
        case .base64, .quotedPrintable, .uuEncode:
            let source = MemoryStream(bytes, writable: false)
            guard let filtered = try? FilteredStream(source) else { return bytes }
            let filter = DecoderFilter.create(encoding)
            _ = try? filtered.add(filter)
            var buffer = [UInt8](repeating: 0, count: 4096)
            var output: [UInt8] = []
            while true {
                let read = (try? filtered.read(&buffer, offset: 0, count: buffer.count)) ?? 0
                if read == 0 { break }
                output.append(contentsOf: buffer[0..<read])
            }
            return output
        default:
            return bytes
        }
    }

    private static func decodeText(_ bytes: [UInt8], encoding: String.Encoding?) -> String? {
        let data = Data(bytes)
        if let encoding {
            if let text = decodeData(data, encoding: encoding) {
                return text
            }
            return decodeData(data, encoding: .isoLatin1)
        }
        if let text = decodeData(data, encoding: .utf8) {
            return text
        }
        return decodeData(data, encoding: .isoLatin1)
    }

    private static func decodeData(_ data: Data, encoding: String.Encoding) -> String? {
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        if data.isEmpty {
            return nil
        }
        var trimmed = data
        for _ in 0..<4 {
            trimmed.removeLast()
            if let text = String(data: trimmed, encoding: encoding) {
                return text
            }
            if trimmed.isEmpty {
                break
            }
        }
        return nil
    }

    private static func headerValue(_ headers: [String: String], name: String) -> String? {
        if let value = headers[name] {
            return value
        }
        let upper = name.uppercased()
        if let value = headers[upper] {
            return value
        }
        return headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Describes the kind of header fetch that was performed.
///
/// This enum indicates what type of header data was requested from the server:
/// all headers, specific header fields, or all headers except certain fields.
public enum HeaderFetchKind: Sendable, Equatable {
    /// All headers were fetched.
    case all

    /// Only the specified header fields were fetched.
    ///
    /// - Parameter fields: The names of the header fields that were fetched.
    case fields([String])

    /// All headers except the specified fields were fetched.
    ///
    /// - Parameter fields: The names of the header fields that were excluded.
    case fieldsNot([String])
}
