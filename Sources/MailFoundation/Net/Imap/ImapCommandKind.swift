//
// ImapCommandKind.swift
//
// IMAP command definitions.
//

public enum ImapCommandKind: Sendable {
    case capability
    case noop
    case login(String, String)
    case authenticate(String, initialResponse: String?)
    case select(String)
    case examine(String)
    case logout
    case create(String)
    case delete(String)
    case rename(String, String)
    case subscribe(String)
    case unsubscribe(String)
    case list(String, String)
    case lsub(String, String)
    case status(String, items: [String])
    case check
    case close
    case expunge
    case namespace
    case id(String)
    case fetch(String, String)
    case store(String, String)
    case copy(String, String)
    case move(String, String)
    case search(String)
    case sort(String)
    case uidFetch(String, String)
    case uidStore(String, String)
    case uidCopy(String, String)
    case uidMove(String, String)
    case uidSearch(String)
    case uidSort(String)
    case enable([String])
    case idle
    case idleDone
    case starttls

    public func command(tag: String) -> ImapCommand {
        switch self {
        case .capability:
            return ImapCommand(tag: tag, name: "CAPABILITY")
        case .noop:
            return ImapCommand(tag: tag, name: "NOOP")
        case let .login(user, password):
            return ImapCommand(tag: tag, name: "LOGIN", arguments: "\(user) \(password)")
        case let .authenticate(mechanism, initialResponse):
            if let response = initialResponse {
                return ImapCommand(tag: tag, name: "AUTHENTICATE", arguments: "\(mechanism) \(response)")
            }
            return ImapCommand(tag: tag, name: "AUTHENTICATE", arguments: mechanism)
        case let .select(mailbox):
            return ImapCommand(tag: tag, name: "SELECT", arguments: mailbox)
        case let .examine(mailbox):
            return ImapCommand(tag: tag, name: "EXAMINE", arguments: mailbox)
        case .logout:
            return ImapCommand(tag: tag, name: "LOGOUT")
        case let .create(mailbox):
            return ImapCommand(tag: tag, name: "CREATE", arguments: mailbox)
        case let .delete(mailbox):
            return ImapCommand(tag: tag, name: "DELETE", arguments: mailbox)
        case let .rename(from, to):
            return ImapCommand(tag: tag, name: "RENAME", arguments: "\(from) \(to)")
        case let .subscribe(mailbox):
            return ImapCommand(tag: tag, name: "SUBSCRIBE", arguments: mailbox)
        case let .unsubscribe(mailbox):
            return ImapCommand(tag: tag, name: "UNSUBSCRIBE", arguments: mailbox)
        case let .list(reference, mailbox):
            return ImapCommand(tag: tag, name: "LIST", arguments: "\(reference) \(mailbox)")
        case let .lsub(reference, mailbox):
            return ImapCommand(tag: tag, name: "LSUB", arguments: "\(reference) \(mailbox)")
        case let .status(mailbox, items):
            let itemList = items.joined(separator: " ")
            return ImapCommand(tag: tag, name: "STATUS", arguments: "\(mailbox) (\(itemList))")
        case .check:
            return ImapCommand(tag: tag, name: "CHECK")
        case .close:
            return ImapCommand(tag: tag, name: "CLOSE")
        case .expunge:
            return ImapCommand(tag: tag, name: "EXPUNGE")
        case .namespace:
            return ImapCommand(tag: tag, name: "NAMESPACE")
        case let .id(arguments):
            return ImapCommand(tag: tag, name: "ID", arguments: arguments)
        case let .fetch(set, items):
            return ImapCommand(tag: tag, name: "FETCH", arguments: "\(set) \(items)")
        case let .store(set, data):
            return ImapCommand(tag: tag, name: "STORE", arguments: "\(set) \(data)")
        case let .copy(set, mailbox):
            return ImapCommand(tag: tag, name: "COPY", arguments: "\(set) \(mailbox)")
        case let .move(set, mailbox):
            return ImapCommand(tag: tag, name: "MOVE", arguments: "\(set) \(mailbox)")
        case let .search(criteria):
            return ImapCommand(tag: tag, name: "SEARCH", arguments: criteria)
        case let .sort(criteria):
            return ImapCommand(tag: tag, name: "SORT", arguments: criteria)
        case let .uidFetch(set, items):
            return ImapCommand(tag: tag, name: "UID FETCH", arguments: "\(set) \(items)")
        case let .uidStore(set, data):
            return ImapCommand(tag: tag, name: "UID STORE", arguments: "\(set) \(data)")
        case let .uidCopy(set, mailbox):
            return ImapCommand(tag: tag, name: "UID COPY", arguments: "\(set) \(mailbox)")
        case let .uidMove(set, mailbox):
            return ImapCommand(tag: tag, name: "UID MOVE", arguments: "\(set) \(mailbox)")
        case let .uidSearch(criteria):
            return ImapCommand(tag: tag, name: "UID SEARCH", arguments: criteria)
        case let .uidSort(criteria):
            return ImapCommand(tag: tag, name: "UID SORT", arguments: criteria)
        case let .enable(capabilities):
            let list = capabilities.joined(separator: " ")
            return ImapCommand(tag: tag, name: "ENABLE", arguments: list)
        case .idle:
            return ImapCommand(tag: tag, name: "IDLE")
        case .idleDone:
            return ImapCommand(tag: tag, name: "DONE")
        case .starttls:
            return ImapCommand(tag: tag, name: "STARTTLS")
        }
    }
}
