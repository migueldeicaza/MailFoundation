//
// ImapEnvelopeCache.swift
//
// Cache for parsed IMAP envelope strings.
//

public actor ImapEnvelopeCache {
    private let maxEntries: Int
    private var storage: [String: ImapEnvelope] = [:]
    private var order: [String] = []

    public init(maxEntries: Int = 128) {
        self.maxEntries = max(1, maxEntries)
    }

    public func envelope(for raw: String) -> ImapEnvelope? {
        if let cached = storage[raw] {
            return cached
        }
        guard let parsed = ImapEnvelope.parse(raw) else { return nil }
        insert(raw: raw, envelope: parsed)
        return parsed
    }

    public func count() -> Int {
        storage.count
    }

    public func clear() {
        storage.removeAll()
        order.removeAll()
    }

    private func insert(raw: String, envelope: ImapEnvelope) {
        storage[raw] = envelope
        order.append(raw)
        if order.count > maxEntries {
            let removed = order.removeFirst()
            storage.removeValue(forKey: removed)
        }
    }
}
