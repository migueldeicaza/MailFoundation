//
// ImapMailboxStatus.swift
//
// Unified mailbox status model.
//

public struct ImapMailboxStatus: Sendable, Equatable {
    public let name: String
    public let mailbox: ImapMailbox?
    public let items: [String: Int]

    public init(name: String, mailbox: ImapMailbox? = nil, items: [String: Int]) {
        self.name = name
        self.mailbox = mailbox
        self.items = items
    }

    public init(status: ImapStatusResponse) {
        self.init(name: status.mailbox, mailbox: nil, items: status.items)
    }

    public init(listStatus: ImapListStatusResponse) {
        self.init(name: listStatus.mailbox.name, mailbox: listStatus.mailbox, items: listStatus.statusItems)
    }

    public func merging(_ other: ImapMailboxStatus) -> ImapMailboxStatus {
        var mergedItems = items
        for (key, value) in other.items {
            mergedItems[key] = value
        }
        return ImapMailboxStatus(
            name: name,
            mailbox: mailbox ?? other.mailbox,
            items: mergedItems
        )
    }
}
