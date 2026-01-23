//
// ImapCommandKind+Helpers.swift
//
// Convenience helpers for IMAP commands.
//

public extension ImapCommandKind {
    static func fetch(_ set: SequenceSet, items: String) -> ImapCommandKind {
        .fetch(set.description, items)
    }

    static func store(_ set: SequenceSet, data: String) -> ImapCommandKind {
        .store(set.description, data)
    }

    static func uidFetch(_ set: UniqueIdSet, items: String) -> ImapCommandKind {
        .uidFetch(set.description, items)
    }

    static func uidStore(_ set: UniqueIdSet, data: String) -> ImapCommandKind {
        .uidStore(set.description, data)
    }

    static func search(_ query: SearchQuery) -> ImapCommandKind {
        .search(query.serialize())
    }

    static func uidSearch(_ query: SearchQuery) -> ImapCommandKind {
        .uidSearch(query.serialize())
    }
}
