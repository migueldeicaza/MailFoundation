//
// ImapFetchRequest.swift
//
// IMAP fetch request helpers.
//

import Foundation
import SwiftMimeKit

public struct FetchRequest: Sendable, Equatable {
    public var items: MessageSummaryItems
    public var headers: [String]?
    public var changedSince: UInt64?

    public init(items: MessageSummaryItems = .none, headers: [String]? = nil, changedSince: UInt64? = nil) {
        self.items = items
        self.headers = headers
        self.changedSince = changedSince
    }

    public init(items: MessageSummaryItems = .none, headers: [HeaderId], changedSince: UInt64? = nil) {
        self.items = items
        self.headers = headers.map { $0.headerName }.filter { !$0.isEmpty }
        self.changedSince = changedSince
    }

    public var imapItemList: String {
        imapItemList(previewFallback: nil)
    }

    public func imapItemList(previewFallback: ImapFetchPartial? = nil) -> String {
        var tokens = items.imapTokens(includePreview: previewFallback == nil)
        if let headerToken = headerFetchToken(headers: headers, requestHeaders: items.contains(.headers), requestReferences: items.contains(.references)) {
            tokens.append(headerToken)
        }
        if let previewFallback {
            tokens.append(ImapFetchBody.section(.text, peek: true, partial: previewFallback))
        }

        guard !tokens.isEmpty else { return "()" }
        if tokens.count == 1 { return tokens[0] }
        return "(\(tokens.joined(separator: " ")))"
    }

    private func headerFetchToken(headers: [String]?, requestHeaders: Bool, requestReferences: Bool) -> String? {
        if let headers {
            let trimmed = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var normalized = trimmed
            if requestReferences {
                let hasReferences = normalized.contains { $0.uppercased() == "REFERENCES" }
                if !hasReferences {
                    normalized.append("REFERENCES")
                }
            }

            if normalized.isEmpty {
                return requestHeaders ? "BODY.PEEK[HEADER]" : nil
            }

            return "BODY.PEEK[HEADER.FIELDS (\(normalized.joined(separator: " ")))]"
        }

        if requestHeaders {
            return "BODY.PEEK[HEADER]"
        }

        if requestReferences {
            return "BODY.PEEK[HEADER.FIELDS (REFERENCES)]"
        }

        return nil
    }
}

private extension MessageSummaryItems {
    func imapTokens(includePreview: Bool) -> [String] {
        var tokens: [String] = []

        if contains(.annotations) { tokens.append("ANNOTATION") }
        if contains(.body) { tokens.append("BODY") }
        if contains(.bodyStructure) { tokens.append("BODYSTRUCTURE") }
        if contains(.envelope) { tokens.append("ENVELOPE") }
        if contains(.flags) { tokens.append("FLAGS") }
        if contains(.internalDate) { tokens.append("INTERNALDATE") }
        if contains(.size) { tokens.append("RFC822.SIZE") }
        if contains(.modSeq) { tokens.append("MODSEQ") }
        if contains(.uniqueId) { tokens.append("UID") }
        if contains(.emailId) { tokens.append("EMAILID") }
        if contains(.threadId) { tokens.append("THREADID") }
        if contains(.gmailMessageId) { tokens.append("X-GM-MSGID") }
        if contains(.gmailThreadId) { tokens.append("X-GM-THRID") }
        if contains(.gmailLabels) { tokens.append("X-GM-LABELS") }
        if includePreview, contains(.previewText) { tokens.append("PREVIEW") }
        if contains(.saveDate) { tokens.append("SAVEDATE") }

        return tokens
    }
}
