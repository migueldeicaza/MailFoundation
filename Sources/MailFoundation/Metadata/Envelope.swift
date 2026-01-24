//
// Envelope.swift
//
// Ported from MailKit (C#) to Swift.
//

import Foundation
import SwiftMimeKit

public enum EnvelopeParseError: Error, Sendable {
    case invalidToken
}

public final class Envelope {
    public let from: InternetAddressList
    public let sender: InternetAddressList
    public let replyTo: InternetAddressList
    public let to: InternetAddressList
    public let cc: InternetAddressList
    public let bcc: InternetAddressList

    public var inReplyTo: String?
    public var date: Date?
    public var messageId: String?
    public var subject: String?
    public var listId: String?
    public var listArchive: String?
    public var listHelp: String?
    public var listOwner: String?
    public var listPost: String?
    public var listSubscribe: String?
    public var listUnsubscribe: String?
    public var listUnsubscribePost: String?
    public var dkimSignatures: [String]
    public var domainKeySignatures: [String]
    public var authenticationResults: [String]
    public var arcAuthenticationResults: [String]
    public var receivedSpf: [String]
    public var arcSeals: [String]
    public var arcMessageSignatures: [String]

    public init() {
        self.from = InternetAddressList()
        self.sender = InternetAddressList()
        self.replyTo = InternetAddressList()
        self.to = InternetAddressList()
        self.cc = InternetAddressList()
        self.bcc = InternetAddressList()
        self.dkimSignatures = []
        self.domainKeySignatures = []
        self.authenticationResults = []
        self.arcAuthenticationResults = []
        self.receivedSpf = []
        self.arcSeals = []
        self.arcMessageSignatures = []
    }

    private static func appendQuoted(_ builder: inout String, _ value: String) {
        builder.append("\"")
        for ch in value {
            if ch == "\\" || ch == "\"" {
                builder.append("\\")
            }
            builder.append(ch)
        }
        builder.append("\"")
    }

    private static func encodeMailbox(_ builder: inout String, mailbox: MailboxAddress) {
        builder.append("(")

        if let name = mailbox.name {
            appendQuoted(&builder, name)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if mailbox.route.count != 0 {
            appendQuoted(&builder, mailbox.route.description)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        let address = mailbox.address
        if let atIndex = address.lastIndex(of: "@") {
            let user = String(address[..<atIndex])
            let domain = String(address[address.index(after: atIndex)...])
            appendQuoted(&builder, user)
            builder.append(" ")
            appendQuoted(&builder, domain)
        } else {
            appendQuoted(&builder, address)
            builder.append(" \"localhost\"")
        }

        builder.append(")")
    }

    private static func encodeGroup(_ builder: inout String, group: GroupAddress) {
        builder.append("(NIL NIL ")
        appendQuoted(&builder, group.name ?? "")
        builder.append(" NIL)")
        encodeAddressListAddresses(&builder, list: group.members)
        builder.append("(NIL NIL NIL NIL)")
    }

    private static func encodeAddressListAddresses(_ builder: inout String, list: InternetAddressList) {
        for address in list {
            if let mailbox = address as? MailboxAddress {
                encodeMailbox(&builder, mailbox: mailbox)
            } else if let group = address as? GroupAddress {
                encodeGroup(&builder, group: group)
            }
        }
    }

    private static func encodeAddressList(_ builder: inout String, list: InternetAddressList) {
        builder.append("(")
        encodeAddressListAddresses(&builder, list: list)
        builder.append(")")
    }

    private func encode(_ builder: inout String) {
        builder.append("(")

        if let date {
            builder.append("\"")
            builder.append(DateUtils.formatDate(date))
            builder.append("\" ")
        } else {
            builder.append("NIL ")
        }

        if let subject {
            Self.appendQuoted(&builder, subject)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if from.count > 0 {
            Self.encodeAddressList(&builder, list: from)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if sender.count > 0 {
            Self.encodeAddressList(&builder, list: sender)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if replyTo.count > 0 {
            Self.encodeAddressList(&builder, list: replyTo)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if to.count > 0 {
            Self.encodeAddressList(&builder, list: to)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if cc.count > 0 {
            Self.encodeAddressList(&builder, list: cc)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if bcc.count > 0 {
            Self.encodeAddressList(&builder, list: bcc)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if let inReplyTo {
            let normalized = Self.normalizeReference(inReplyTo)
            Self.appendQuoted(&builder, normalized)
            builder.append(" ")
        } else {
            builder.append("NIL ")
        }

        if let messageId {
            let normalized = Self.normalizeReference(messageId)
            Self.appendQuoted(&builder, normalized)
        } else {
            builder.append("NIL")
        }

        builder.append(")")
    }

    public func toString() -> String {
        var builder = ""
        encode(&builder)
        return builder
    }

    private static func isNil(_ bytes: [UInt8], index: Int) -> Bool {
        guard index + 2 < bytes.count else {
            return false
        }
        let n = bytes[index]
        let i = bytes[index + 1]
        let l = bytes[index + 2]
        return (n == 0x4E || n == 0x6E) && (i == 0x49 || i == 0x69) && (l == 0x4C || l == 0x6C)
    }

    private static func skipSpaces(_ bytes: [UInt8], index: inout Int) {
        while index < bytes.count, bytes[index] == 0x20 {
            index += 1
        }
    }

    private static func tryParseNString(_ bytes: [UInt8], index: inout Int) -> (success: Bool, value: String?) {
        skipSpaces(bytes, index: &index)
        guard index < bytes.count else {
            return (false, nil)
        }

        if bytes[index] == 0x7B { // '{'
            return tryParseLiteralString(bytes, index: &index)
        }

        if bytes[index] != 0x22 {
            if index + 3 <= bytes.count, isNil(bytes, index: index) {
                index += 3
                return (true, nil)
            }
            return (false, nil)
        }

        index += 1
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64)
        var escaped = false

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 && !escaped {
                break
            }

            if escaped || byte != 0x5C {
                buffer.append(byte)
                escaped = false
            } else {
                escaped = true
            }

            index += 1
        }

        guard index < bytes.count else {
            return (false, nil)
        }

        let string = String(decoding: buffer, as: UTF8.self)
        index += 1
        return (true, string)
    }

    private static func tryParseLiteralString(_ bytes: [UInt8], index: inout Int) -> (success: Bool, value: String?) {
        guard index < bytes.count, bytes[index] == 0x7B else {
            return (false, nil)
        }

        index += 1
        var length: Int = 0
        var hasDigits = false

        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 0x30, byte <= 0x39 {
                hasDigits = true
                length = (length * 10) + Int(byte - 0x30)
                index += 1
                continue
            }
            if byte == 0x2B { // '+'
                index += 1
                continue
            }
            if byte == 0x7D { // '}'
                index += 1
                break
            }
            return (false, nil)
        }

        guard hasDigits else { return (false, nil) }
        guard index + 1 < bytes.count, bytes[index] == 0x0D, bytes[index + 1] == 0x0A else {
            return (false, nil)
        }
        index += 2

        guard index + length <= bytes.count else {
            return (false, nil)
        }

        let literalBytes = bytes[index..<(index + length)]
        index += length
        let string = String(decoding: literalBytes, as: UTF8.self)
        return (true, string)
    }

    private static func tryParseAddress(_ bytes: [UInt8], index: inout Int) -> (success: Bool, value: InternetAddress?) {
        guard index < bytes.count, bytes[index] == 0x28 else {
            return (false, nil)
        }

        index += 1

        let nameResult = tryParseNString(bytes, index: &index)
        guard nameResult.success else { return (false, nil) }
        let routeResult = tryParseNString(bytes, index: &index)
        guard routeResult.success else { return (false, nil) }
        let userResult = tryParseNString(bytes, index: &index)
        guard userResult.success else { return (false, nil) }
        let domainResult = tryParseNString(bytes, index: &index)
        guard domainResult.success else { return (false, nil) }

        skipSpaces(bytes, index: &index)
        guard index < bytes.count, bytes[index] == 0x29 else {
            return (false, nil)
        }
        index += 1

        if let domain = domainResult.value {
            let user = userResult.value ?? ""
            let address = (domain == "localhost") ? user : "\(user)@\(domain)"
            if let routeText = routeResult.value {
                var route: DomainList?
                if DomainList.tryParse(routeText, route: &route), let route {
                    let mailbox = MailboxAddress(name: nameResult.value, route: Array(route), address: address)
                    return (true, mailbox)
                }
            }
            return (true, MailboxAddress(name: nameResult.value, address: address))
        }

        if let user = userResult.value {
            return (true, GroupAddress(name: user))
        }

        return (true, nil)
    }

    private static func tryParseAddressList(_ bytes: [UInt8], index: inout Int) -> (success: Bool, value: InternetAddressList?) {
        skipSpaces(bytes, index: &index)
        guard index < bytes.count else {
            return (false, nil)
        }

        if bytes[index] != 0x28 {
            if index + 3 <= bytes.count, isNil(bytes, index: index) {
                index += 3
                return (true, InternetAddressList())
            }
            return (false, nil)
        }

        index += 1
        guard index < bytes.count else {
            return (false, nil)
        }

        let list = InternetAddressList()
        var stack: [InternetAddressList] = [list]
        var sp = 0

        while index < bytes.count {
            if bytes[index] == 0x29 {
                break
            }

            let addressResult = tryParseAddress(bytes, index: &index)
            guard addressResult.success else { return (false, nil) }

            if let address = addressResult.value {
                stack[sp].add(address)
                if let group = address as? GroupAddress {
                    stack.append(group.members)
                    sp += 1
                }
            } else if sp > 0 {
                stack.removeLast()
                sp -= 1
            }

            skipSpaces(bytes, index: &index)
        }

        guard index < bytes.count, bytes[index] == 0x29 else {
            return (false, nil)
        }
        index += 1
        return (true, list)
    }

    private static func normalizeReference(_ value: String) -> String {
        if value.count > 1, value.first != "<", value.last != ">" {
            return "<\(value)>"
        }
        return value
    }

    private static func firstReference(in value: String) -> String? {
        MessageIdList.parseAll(value).first
    }

    private static func tryParseEnvelope(_ bytes: [UInt8], index: inout Int) -> (success: Bool, value: Envelope?) {
        skipSpaces(bytes, index: &index)
        guard index < bytes.count else {
            return (false, nil)
        }

        if bytes[index] != 0x28 {
            if index + 3 <= bytes.count, isNil(bytes, index: index) {
                index += 3
                return (true, nil)
            }
            return (false, nil)
        }

        index += 1

        let dateResult = tryParseNString(bytes, index: &index)
        guard dateResult.success else { return (false, nil) }
        var parsedDate: Date?
        if let dateText = dateResult.value {
            guard let date = DateUtils.tryParse(dateText) else {
                return (false, nil)
            }
            parsedDate = date
        }

        let subjectResult = tryParseNString(bytes, index: &index)
        guard subjectResult.success else { return (false, nil) }

        let fromResult = tryParseAddressList(bytes, index: &index)
        guard fromResult.success else { return (false, nil) }
        let senderResult = tryParseAddressList(bytes, index: &index)
        guard senderResult.success else { return (false, nil) }
        let replyToResult = tryParseAddressList(bytes, index: &index)
        guard replyToResult.success else { return (false, nil) }
        let toResult = tryParseAddressList(bytes, index: &index)
        guard toResult.success else { return (false, nil) }
        let ccResult = tryParseAddressList(bytes, index: &index)
        guard ccResult.success else { return (false, nil) }
        let bccResult = tryParseAddressList(bytes, index: &index)
        guard bccResult.success else { return (false, nil) }

        let inReplyToResult = tryParseNString(bytes, index: &index)
        guard inReplyToResult.success else { return (false, nil) }
        let messageIdResult = tryParseNString(bytes, index: &index)
        guard messageIdResult.success else { return (false, nil) }

        guard index < bytes.count, bytes[index] == 0x29 else {
            return (false, nil)
        }
        index += 1

        let envelope = Envelope()
        envelope.date = parsedDate
        envelope.subject = subjectResult.value
        if let list = fromResult.value { envelope.from.addRange(Array(list)) }
        if let list = senderResult.value { envelope.sender.addRange(Array(list)) }
        if let list = replyToResult.value { envelope.replyTo.addRange(Array(list)) }
        if let list = toResult.value { envelope.to.addRange(Array(list)) }
        if let list = ccResult.value { envelope.cc.addRange(Array(list)) }
        if let list = bccResult.value { envelope.bcc.addRange(Array(list)) }

        if let inReplyTo = inReplyToResult.value {
            envelope.inReplyTo = firstReference(in: inReplyTo) ?? inReplyTo
        }
        if let messageId = messageIdResult.value {
            envelope.messageId = firstReference(in: messageId) ?? messageId
        }

        return (true, envelope)
    }

    public static func tryParse(_ text: String) -> Envelope? {
        var index = 0
        let bytes = Array(text.utf8)
        let result = tryParseEnvelope(bytes, index: &index)
        guard result.success, index == bytes.count else {
            return nil
        }
        return result.value
    }

    public static func parse(_ text: String) throws -> Envelope {
        guard let envelope = tryParse(text) else {
            throw EnvelopeParseError.invalidToken
        }
        return envelope
    }
}

extension Envelope: CustomStringConvertible {
    public var description: String {
        toString()
    }
}
