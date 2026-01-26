//
// ImapEnvelope.swift
//
// Strongly typed IMAP ENVELOPE model.
//

import Foundation
import MimeFoundation

public struct ImapEnvelope: Sendable, Equatable {
    public let date: Date?
    public let subject: String?
    public let from: [ImapAddress]
    public let sender: [ImapAddress]
    public let replyTo: [ImapAddress]
    public let to: [ImapAddress]
    public let cc: [ImapAddress]
    public let bcc: [ImapAddress]
    public let inReplyTo: String?
    public let messageId: String?

    public init(
        date: Date?,
        subject: String?,
        from: [ImapAddress],
        sender: [ImapAddress],
        replyTo: [ImapAddress],
        to: [ImapAddress],
        cc: [ImapAddress],
        bcc: [ImapAddress],
        inReplyTo: String?,
        messageId: String?
    ) {
        self.date = date
        self.subject = subject
        self.from = from
        self.sender = sender
        self.replyTo = replyTo
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.inReplyTo = inReplyTo
        self.messageId = messageId
    }

    public static func parse(_ text: String) -> ImapEnvelope? {
        guard let envelope = try? Envelope(parsing: text) else { return nil }
        return ImapEnvelope(envelope: envelope)
    }

    public init(envelope: Envelope) {
        self.date = envelope.date
        self.subject = envelope.subject
        self.from = ImapEnvelope.convert(envelope.from)
        self.sender = ImapEnvelope.convert(envelope.sender)
        self.replyTo = ImapEnvelope.convert(envelope.replyTo)
        self.to = ImapEnvelope.convert(envelope.to)
        self.cc = ImapEnvelope.convert(envelope.cc)
        self.bcc = ImapEnvelope.convert(envelope.bcc)
        self.inReplyTo = envelope.inReplyTo
        self.messageId = envelope.messageId
    }

    private static func convert(_ list: InternetAddressList) -> [ImapAddress] {
        var result: [ImapAddress] = []
        for address in list {
            if let mailbox = address as? MailboxAddress {
                result.append(.mailbox(ImapMailboxAddress(mailbox: mailbox)))
            } else if let group = address as? GroupAddress {
                let members = group.members.compactMap { member in
                    (member as? MailboxAddress).map(ImapMailboxAddress.init)
                }
                result.append(.group(ImapGroupAddress(name: group.name, members: members)))
            }
        }
        return result
    }
}

public enum ImapAddress: Sendable, Equatable {
    case mailbox(ImapMailboxAddress)
    case group(ImapGroupAddress)
}

public struct ImapMailboxAddress: Sendable, Equatable {
    public let name: String?
    public let route: String?
    public let mailbox: String?
    public let host: String?

    public init(name: String?, route: String?, mailbox: String?, host: String?) {
        self.name = name
        self.route = route
        self.mailbox = mailbox
        self.host = host
    }

    public init(mailbox: MailboxAddress) {
        self.name = mailbox.name
        self.route = mailbox.route.isEmpty ? nil : mailbox.route.description
        if let atIndex = mailbox.address.firstIndex(of: "@") {
            let user = String(mailbox.address[..<atIndex])
            let host = String(mailbox.address[mailbox.address.index(after: atIndex)...])
            self.mailbox = user.isEmpty ? nil : user
            self.host = host.isEmpty ? nil : host
        } else {
            self.mailbox = mailbox.address.isEmpty ? nil : mailbox.address
            self.host = nil
        }
    }

    public var address: String? {
        guard let mailbox else { return nil }
        if let host {
            return "\(mailbox)@\(host)"
        }
        return mailbox
    }
}

public struct ImapGroupAddress: Sendable, Equatable {
    public let name: String?
    public let members: [ImapMailboxAddress]
}
