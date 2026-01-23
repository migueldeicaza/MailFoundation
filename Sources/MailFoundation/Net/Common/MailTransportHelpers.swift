//
// MailTransportHelpers.swift
//
// Message envelope helpers for mail transports.
//

import Foundation
import SwiftMimeKit

public enum MailTransportError: Error, Sendable, Equatable {
    case missingSender
    case missingRecipients
}

public struct MailTransportEnvelope {
    public let sender: MailboxAddress
    public let recipients: [MailboxAddress]
    public let data: [UInt8]

    public init(sender: MailboxAddress, recipients: [MailboxAddress], data: [UInt8]) {
        self.sender = sender
        self.recipients = recipients
        self.data = data
    }
}

public enum MailTransportEnvelopeBuilder {
    public static func build(
        for message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> MailTransportEnvelope {
        let sender = try resolveSender(for: message)
        let recipients = try resolveRecipients(for: message)
        let data = try encodeMessage(message, options: options, progress: progress)
        return MailTransportEnvelope(sender: sender, recipients: recipients, data: data)
    }

    public static func resolveSender(for message: MimeMessage) throws -> MailboxAddress {
        let headers = message.headers
        if let mailbox = firstMailbox(in: headers, id: .resentSender) {
            return mailbox
        }
        if let mailbox = mailboxes(in: headers, id: .resentFrom).first {
            return mailbox
        }
        if let mailbox = firstMailbox(in: headers, id: .sender) {
            return mailbox
        }
        if let mailbox = message.from.mailboxes.first {
            return mailbox
        }
        if let mailbox = mailboxes(in: headers, id: .from).first {
            return mailbox
        }
        throw MailTransportError.missingSender
    }

    public static func resolveRecipients(for message: MimeMessage) throws -> [MailboxAddress] {
        let headers = message.headers
        let resentSender = firstMailbox(in: headers, id: .resentSender)
        let resentFrom = mailboxes(in: headers, id: .resentFrom)
        let useResent = resentSender != nil || !resentFrom.isEmpty

        var unique: Set<String> = []
        var recipients: [MailboxAddress] = []

        if useResent {
            addUnique(&recipients, unique: &unique, mailboxes: mailboxes(in: headers, id: .resentTo))
            addUnique(&recipients, unique: &unique, mailboxes: mailboxes(in: headers, id: .resentCc))
            addUnique(&recipients, unique: &unique, mailboxes: mailboxes(in: headers, id: .resentBcc))
        } else {
            addUnique(&recipients, unique: &unique, mailboxes: message.to.mailboxes)
            addUnique(&recipients, unique: &unique, mailboxes: message.cc.mailboxes)
            addUnique(&recipients, unique: &unique, mailboxes: mailboxes(in: headers, id: .bcc))
        }

        guard !recipients.isEmpty else {
            throw MailTransportError.missingRecipients
        }

        return recipients
    }

    public static func encodeMessage(
        _ message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> [UInt8] {
        let stream = MemoryStream()
        try message.writeTo(options, stream)
        let data = stream.toByteArray()
        if let progress {
            let size = Int64(data.count)
            progress.report(bytesTransferred: size, totalSize: size)
        }
        return data
    }
}

public extension MailTransportBase {
    func prepareEnvelope(
        for message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> (from: MailboxAddress, recipients: [MailboxAddress], data: [UInt8]) {
        let sender = try MailTransportEnvelopeBuilder.resolveSender(for: message)
        let recipients = try MailTransportEnvelopeBuilder.resolveRecipients(for: message)
        let data = try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
        return (sender, recipients, data)
    }

    func resolveSender(for message: MimeMessage) throws -> MailboxAddress {
        try MailTransportEnvelopeBuilder.resolveSender(for: message)
    }

    func resolveRecipients(for message: MimeMessage) throws -> [MailboxAddress] {
        try MailTransportEnvelopeBuilder.resolveRecipients(for: message)
    }

    func encodeMessage(
        _ message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> [UInt8] {
        try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
    }
}

public extension MessageTransport {
    func sendMessage(
        _ message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws {
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        try sendMessage(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data
        )
    }
}

@available(macOS 10.15, iOS 13.0, *)
public extension AsyncMessageTransport {
    func sendMessage(
        _ message: MimeMessage,
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) async throws {
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        try await sendMessage(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data
        )
    }
}

private func firstMailbox(in headers: HeaderList, id: HeaderId) -> MailboxAddress? {
    for header in headers where header.id == id {
        if let mailbox = AddressParser.tryParseMailbox(header.value) {
            return mailbox
        }
    }
    return nil
}

private func mailboxes(in headers: HeaderList, id: HeaderId) -> [MailboxAddress] {
    var result: [MailboxAddress] = []
    for header in headers where header.id == id {
        if let list = AddressParser.tryParseList(header.value) {
            result.append(contentsOf: list.mailboxes)
        }
    }
    return result
}

private func addUnique(_ recipients: inout [MailboxAddress], unique: inout Set<String>, mailboxes: [MailboxAddress]) {
    for mailbox in mailboxes {
        let key = mailbox.address.lowercased()
        if unique.insert(key).inserted {
            recipients.append(mailbox)
        }
    }
}
