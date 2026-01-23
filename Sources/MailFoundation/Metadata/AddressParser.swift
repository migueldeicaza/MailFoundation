//
// AddressParser.swift
//
// Address parsing helpers backed by SwiftMimeKit.
//

import SwiftMimeKit

public enum AddressParserError: Error, Sendable {
    case noMailboxFound
}

public enum AddressParser {
    public static func parseList(_ value: String) throws -> InternetAddressList {
        try InternetAddressList.parse(value)
    }

    public static func tryParseList(_ value: String) -> InternetAddressList? {
        try? InternetAddressList.parse(value)
    }

    public static func parseMailbox(_ value: String) throws -> MailboxAddress {
        let list = try InternetAddressList.parse(value)
        for address in list {
            if let mailbox = address as? MailboxAddress {
                return mailbox
            }
        }
        throw AddressParserError.noMailboxFound
    }

    public static func tryParseMailbox(_ value: String) -> MailboxAddress? {
        guard let list = tryParseList(value) else { return nil }
        for address in list {
            if let mailbox = address as? MailboxAddress {
                return mailbox
            }
        }
        return nil
    }
}
