//
// AddressParser.swift
//
// Address parsing helpers backed by MimeFoundation.
//

import MimeFoundation

public enum AddressParserError: Error, Sendable {
    case noMailboxFound
}

public enum AddressParser {
    public static func parseList(_ value: String) throws -> InternetAddressList {
        try InternetAddressList(parsing: value)
    }

    public static func parseMailbox(_ value: String) throws -> MailboxAddress {
        let list = try InternetAddressList(parsing: value)
        for address in list {
            if let mailbox = address as? MailboxAddress {
                return mailbox
            }
        }
        throw AddressParserError.noMailboxFound
    }
}
