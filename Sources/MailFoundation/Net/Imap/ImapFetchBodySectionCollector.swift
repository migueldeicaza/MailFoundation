//
// ImapFetchBodySectionCollector.swift
//
// Aggregate BODY[] literal responses per FETCH sequence.
//

public struct ImapFetchBodySectionResult: Sendable, Equatable {
    public let sequence: Int
    public let sections: [ImapFetchBodySectionPayload]
}

public struct ImapFetchBodySectionPayload: Sendable, Equatable {
    public let section: ImapFetchBodySection?
    public let peek: Bool
    public let partial: ImapFetchPartial?
    public let data: [UInt8]
}

public actor ImapFetchBodySectionCollector {
    private var pending: [Int: [ImapFetchBodySectionPayload]] = [:]

    public init() {}

    public func ingest(_ message: ImapLiteralMessage) -> ImapFetchBodySectionResult? {
        guard let parsed = ImapFetchBodySectionResponse.parse(message) else { return nil }
        let payload = ImapFetchBodySectionPayload(
            section: parsed.section,
            peek: parsed.peek,
            partial: parsed.partial,
            data: parsed.data
        )
        pending[parsed.sequence, default: []].append(payload)
        return nil
    }

    public func ingest(_ messages: [ImapLiteralMessage]) -> [ImapFetchBodySectionResult] {
        var results: [ImapFetchBodySectionResult] = []
        for message in messages {
            _ = ingest(message)
        }
        for (sequence, sections) in pending {
            results.append(ImapFetchBodySectionResult(sequence: sequence, sections: sections))
        }
        pending.removeAll()
        return results.sorted { $0.sequence < $1.sequence }
    }
}
