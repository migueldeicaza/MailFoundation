//
// ImapFlagChange.swift
//
// Structured FLAG update parsing (typically from UID STORE responses).
//

public struct ImapFlagChange: Sendable, Equatable {
    public let sequence: Int
    public let uid: UInt32?
    public let flags: [String]
    public let modSeq: UInt64?

    public init(sequence: Int, uid: UInt32?, flags: [String], modSeq: UInt64?) {
        self.sequence = sequence
        self.uid = uid
        self.flags = flags
        self.modSeq = modSeq
    }

    public static func parse(_ fetch: ImapFetchResponse) -> ImapFlagChange? {
        let upper = fetch.payload.uppercased()
        guard upper.contains("FLAGS") else { return nil }
        guard let attributes = ImapFetchAttributes.parse(fetch) else { return nil }
        return ImapFlagChange(
            sequence: fetch.sequence,
            uid: attributes.uid,
            flags: attributes.flags,
            modSeq: attributes.modSeq
        )
    }

    public static func parse(_ line: String) -> ImapFlagChange? {
        guard let fetch = ImapFetchResponse.parse(line) else { return nil }
        return parse(fetch)
    }
}

public extension ImapFetchResult {
    func flagChanges() -> [ImapFlagChange] {
        responses.compactMap(ImapFlagChange.parse)
    }
}
