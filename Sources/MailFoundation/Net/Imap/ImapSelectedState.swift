//
// ImapSelectedState.swift
//
// Track selected mailbox state (UIDNEXT/UIDVALIDITY/HIGHESTMODSEQ).
//

public struct ImapSelectedState: Sendable, Equatable {
    public var uidNext: UInt32?
    public var uidValidity: UInt32?
    public var highestModSeq: UInt64?
    public var messageCount: Int?
    public var recentCount: Int?
    public var lastExpungeSequence: Int?
    public var uidBySequence: [Int: UniqueId]
    public var sequenceByUid: [UniqueId: Int]
    public var uidSet: UniqueIdSet

    public init(
        uidNext: UInt32? = nil,
        uidValidity: UInt32? = nil,
        highestModSeq: UInt64? = nil,
        messageCount: Int? = nil,
        recentCount: Int? = nil,
        lastExpungeSequence: Int? = nil,
        uidBySequence: [Int: UniqueId] = [:],
        sequenceByUid: [UniqueId: Int] = [:],
        uidSet: UniqueIdSet? = nil
    ) {
        self.uidNext = uidNext
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.messageCount = messageCount
        self.recentCount = recentCount
        self.lastExpungeSequence = lastExpungeSequence
        self.uidBySequence = uidBySequence
        self.sequenceByUid = sequenceByUid
        if let uidSet {
            self.uidSet = uidSet
        } else {
            var snapshot = UniqueIdSet(validity: uidValidity ?? 0, sortOrder: .ascending)
            for uid in uidBySequence.values {
                snapshot.add(uid)
            }
            self.uidSet = snapshot
        }
    }

    public mutating func apply(response: ImapResponse) {
        let codes = ImapResponseCode.parseAll(response.text)
        for code in codes {
            switch code.kind {
            case .uidNext(let value):
                uidNext = value
            case .uidValidity(let value):
                applyUidValidity(value)
            case .highestModSeq(let value):
                highestModSeq = max(highestModSeq ?? 0, value)
            case .copyUid:
                break
            }
        }
    }

    public mutating func apply(status: ImapStatusResponse) {
        uidNext = extractUInt32(status.items, key: "UIDNEXT") ?? uidNext
        if let value = extractUInt32(status.items, key: "UIDVALIDITY") {
            applyUidValidity(value)
        }
        if let messages = extractInt(status.items, key: "MESSAGES") {
            messageCount = messages
        }
        if let recent = extractInt(status.items, key: "RECENT") {
            recentCount = recent
        }
        if let modSeq = extractUInt64(status.items, key: "HIGHESTMODSEQ") {
            highestModSeq = max(highestModSeq ?? 0, modSeq)
        }
    }

    public mutating func apply(listStatus: ImapListStatusResponse) {
        uidNext = extractUInt32(listStatus.statusItems, key: "UIDNEXT") ?? uidNext
        if let value = extractUInt32(listStatus.statusItems, key: "UIDVALIDITY") {
            applyUidValidity(value)
        }
        if let messages = extractInt(listStatus.statusItems, key: "MESSAGES") {
            messageCount = messages
        }
        if let recent = extractInt(listStatus.statusItems, key: "RECENT") {
            recentCount = recent
        }
        if let modSeq = extractUInt64(listStatus.statusItems, key: "HIGHESTMODSEQ") {
            highestModSeq = max(highestModSeq ?? 0, modSeq)
        }
    }

    public mutating func apply(modSeq: ImapModSeqResponse) {
        highestModSeq = max(highestModSeq ?? 0, modSeq.value)
    }

    public mutating func apply(event: ImapQresyncEvent) {
        if case let .fetch(fetch) = event {
            highestModSeq = max(highestModSeq ?? 0, fetch.modSeq)
        }
    }

    public mutating func apply(event: ImapIdleEvent) {
        switch event {
        case .exists(let count):
            messageCount = count
        case .recent(let count):
            recentCount = count
        case .expunge(let sequence):
            lastExpungeSequence = sequence
            if let current = messageCount, current > 0 {
                messageCount = current - 1
            }
            applyExpunge(sequence: sequence)
        case .flags, .status, .other:
            break
        }
    }

    public mutating func applyFetch(sequence: Int, uid: UInt32?, modSeq: UInt64?) {
        if let modSeq {
            highestModSeq = max(highestModSeq ?? 0, modSeq)
        }
        guard let uid, uid > 0 else { return }
        let validity = uidValidity ?? 0
        let uniqueId = UniqueId(validity: validity, id: uid)
        uidBySequence[sequence] = uniqueId
        sequenceByUid[uniqueId] = sequence
        uidSet.add(uniqueId)
    }

    private func extractUInt32(_ items: [String: Int], key: String) -> UInt32? {
        guard let value = items[key] else { return nil }
        return UInt32(value)
    }

    private func extractUInt64(_ items: [String: Int], key: String) -> UInt64? {
        guard let value = items[key] else { return nil }
        return UInt64(value)
    }

    private func extractInt(_ items: [String: Int], key: String) -> Int? {
        items[key]
    }

    private mutating func applyExpunge(sequence: Int) {
        guard !uidBySequence.isEmpty else { return }
        var nextBySequence: [Int: UniqueId] = [:]
        var removedUid: UniqueId?
        for (key, value) in uidBySequence {
            if key == sequence {
                removedUid = value
                continue
            }
            let newKey = key > sequence ? key - 1 : key
            nextBySequence[newKey] = value
        }
        uidBySequence = nextBySequence
        var nextByUid: [UniqueId: Int] = [:]
        for (sequence, uid) in nextBySequence {
            nextByUid[uid] = sequence
        }
        sequenceByUid = nextByUid
        if let removedUid {
            _ = uidSet.remove(removedUid)
        }
    }

    private mutating func applyUidValidity(_ value: UInt32) {
        if uidValidity != value {
            uidValidity = value
            uidBySequence.removeAll()
            sequenceByUid.removeAll()
            uidSet = UniqueIdSet(validity: value, sortOrder: .ascending)
        }
    }
}

public extension ImapSelectedState {
    static func == (lhs: ImapSelectedState, rhs: ImapSelectedState) -> Bool {
        lhs.uidNext == rhs.uidNext &&
            lhs.uidValidity == rhs.uidValidity &&
            lhs.highestModSeq == rhs.highestModSeq &&
            lhs.messageCount == rhs.messageCount &&
            lhs.recentCount == rhs.recentCount &&
            lhs.lastExpungeSequence == rhs.lastExpungeSequence &&
            lhs.uidBySequence == rhs.uidBySequence &&
            lhs.sequenceByUid == rhs.sequenceByUid &&
            lhs.uidSet.validity == rhs.uidSet.validity &&
            lhs.uidSet.description == rhs.uidSet.description
    }
}

public extension ImapSelectedState {
    func uidSetSnapshot(sortOrder: SortOrder = .ascending) -> UniqueIdSet {
        var snapshot = UniqueIdSet(validity: uidValidity ?? uidSet.validity, sortOrder: sortOrder)
        for uid in uidSet {
            snapshot.add(uid)
        }
        return snapshot
    }
}
