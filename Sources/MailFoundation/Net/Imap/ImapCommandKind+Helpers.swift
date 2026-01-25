//
// ImapCommandKind+Helpers.swift
//
// Convenience helpers for IMAP commands.
//

public extension ImapCommandKind {
    static func namespace() -> ImapCommandKind {
        .namespace
    }

    static func id(_ parameters: [String: String?]? = nil) -> ImapCommandKind {
        .id(ImapId.buildArguments(parameters))
    }

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

    static func copy(_ set: SequenceSet, mailbox: String) -> ImapCommandKind {
        .copy(set.description, mailbox)
    }

    static func uidCopy(_ set: UniqueIdSet, mailbox: String) -> ImapCommandKind {
        .uidCopy(set.description, mailbox)
    }

    static func move(_ set: SequenceSet, mailbox: String) -> ImapCommandKind {
        .move(set.description, mailbox)
    }

    static func uidMove(_ set: UniqueIdSet, mailbox: String) -> ImapCommandKind {
        .uidMove(set.description, mailbox)
    }

    static func search(_ query: SearchQuery) -> ImapCommandKind {
        .search(query.serialize())
    }

    static func sort(_ query: SearchQuery, orderBy: [OrderBy], charset: String = "UTF-8") throws -> ImapCommandKind {
        let criteria = try ImapSort.buildArguments(orderBy: orderBy, query: query, charset: charset)
        return .sort(criteria)
    }

    static func uidSearch(_ query: SearchQuery) -> ImapCommandKind {
        .uidSearch(query.serialize())
    }

    static func uidSort(_ query: SearchQuery, orderBy: [OrderBy], charset: String = "UTF-8") throws -> ImapCommandKind {
        let criteria = try ImapSort.buildArguments(orderBy: orderBy, query: query, charset: charset)
        return .uidSort(criteria)
    }
}
