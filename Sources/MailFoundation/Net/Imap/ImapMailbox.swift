//
// ImapMailbox.swift
//
// IMAP mailbox attribute modeling.
//

public enum ImapMailboxAttribute: Sendable, Equatable {
    case hasChildren
    case hasNoChildren
    case noSelect
    case noInferiors
    case marked
    case unmarked
    case nonExistent
    case subscribed
    case remote
    case noRename
    case readOnly
    case noMail
    case noAccess
    case inbox
    case all
    case archive
    case drafts
    case flagged
    case junk
    case sent
    case trash
    case important
    case other(String)

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("\\") ? String(trimmed.dropFirst()) : trimmed
        switch normalized.uppercased() {
        case "HASCHILDREN":
            self = .hasChildren
        case "HASNOCHILDREN":
            self = .hasNoChildren
        case "NOSELECT":
            self = .noSelect
        case "NOINFERIORS":
            self = .noInferiors
        case "MARKED":
            self = .marked
        case "UNMARKED":
            self = .unmarked
        case "NONEXISTENT":
            self = .nonExistent
        case "SUBSCRIBED":
            self = .subscribed
        case "REMOTE":
            self = .remote
        case "NORENAME":
            self = .noRename
        case "READ-ONLY", "READONLY":
            self = .readOnly
        case "NOMAIL":
            self = .noMail
        case "NOACCESS":
            self = .noAccess
        case "INBOX":
            self = .inbox
        case "ALL":
            self = .all
        case "ARCHIVE":
            self = .archive
        case "DRAFTS":
            self = .drafts
        case "FLAGGED":
            self = .flagged
        case "JUNK":
            self = .junk
        case "SENT":
            self = .sent
        case "TRASH":
            self = .trash
        case "IMPORTANT":
            self = .important
        default:
            self = .other(normalized)
        }
    }

    public var isSpecialUse: Bool {
        switch self {
        case .all, .archive, .drafts, .flagged, .junk, .sent, .trash, .important:
            return true
        default:
            return false
        }
    }
}

public struct ImapMailbox: Sendable, Equatable {
    public let kind: ImapMailboxListKind
    public let name: String
    public let delimiter: String?
    public let rawAttributes: [String]
    public let attributes: [ImapMailboxAttribute]

    public init(kind: ImapMailboxListKind, name: String, delimiter: String?, attributes: [String]) {
        self.kind = kind
        self.name = name
        self.delimiter = delimiter
        self.rawAttributes = attributes
        self.attributes = attributes.map { ImapMailboxAttribute(rawValue: $0) }
    }

    public func hasAttribute(_ attribute: ImapMailboxAttribute) -> Bool {
        attributes.contains(attribute)
    }

    public var specialUse: ImapMailboxAttribute? {
        attributes.first { $0.isSpecialUse }
    }

    public var isSelectable: Bool {
        !hasAttribute(.noSelect) && !hasAttribute(.nonExistent)
    }

    public var hasChildren: Bool {
        hasAttribute(.hasChildren)
    }
}

public extension ImapMailboxListResponse {
    func toMailbox() -> ImapMailbox {
        ImapMailbox(kind: kind, name: name, delimiter: delimiter, attributes: attributes)
    }
}
