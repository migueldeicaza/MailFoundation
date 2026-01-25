//
// ImapSearchResponse.swift
//
// IMAP SEARCH response parsing helpers.
//

public struct ImapSearchResponse: Sendable, Equatable {
    public let ids: [UInt32]
    public let count: Int?
    public let min: UInt32?
    public let max: UInt32?
    public let isUid: Bool

    public init(
        ids: [UInt32],
        count: Int? = nil,
        min: UInt32? = nil,
        max: UInt32? = nil,
        isUid: Bool = false
    ) {
        self.ids = ids
        self.count = count
        self.min = min
        self.max = max
        self.isUid = isUid
    }

    public init(esearch: ImapESearchResponse, defaultIsUid: Bool = false) {
        self.ids = esearch.ids
        self.count = esearch.count
        self.min = esearch.min
        self.max = esearch.max
        self.isUid = esearch.isUid || defaultIsUid
    }

    public static func parse(_ line: String) -> ImapSearchResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }
        let upper = trimmed.uppercased()
        let prefixLength: Int
        if upper.hasPrefix("* SEARCH") {
            prefixLength = 8
        } else if upper.hasPrefix("* SORT") {
            prefixLength = 6
        } else {
            return nil
        }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: prefixLength)
        let remainder = trimmed[startIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else {
            return ImapSearchResponse(ids: [])
        }

        let tokens = remainder.split(separator: " ", omittingEmptySubsequences: true)
        var ids: [UInt32] = []
        for token in tokens {
            if let id = UInt32(token) {
                ids.append(id)
            }
        }
        return ImapSearchResponse(ids: ids)
    }
}

public enum ImapSearchIdSet: Sendable {
    case sequence(SequenceSet)
    case uid(UniqueIdSet)
}

public extension ImapSearchResponse {
    func sequenceSet() -> SequenceSet {
        SequenceSet(ids.map { Int($0) })
    }

    func uniqueIdSet(validity: UInt32 = 0) -> UniqueIdSet {
        let uniqueIds = ids.compactMap { UniqueId.tryParse(String($0), validity: validity) }
        var set = UniqueIdSet(validity: validity)
        set.add(contentsOf: uniqueIds)
        return set
    }

    func idSet(validity: UInt32 = 0) -> ImapSearchIdSet {
        if isUid {
            return .uid(uniqueIdSet(validity: validity))
        }
        return .sequence(sequenceSet())
    }
}
