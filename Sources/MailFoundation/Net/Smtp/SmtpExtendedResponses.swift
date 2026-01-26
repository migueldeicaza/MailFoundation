//
// SmtpExtendedResponses.swift
//
// Helpers for parsing richer SMTP responses (VRFY/EXPN/HELP).
//

import MimeFoundation

public struct SmtpVrfyResult: @unchecked Sendable {
    public let response: SmtpResponse
    public let mailboxes: [MailboxAddress]
    public let rawLines: [String]

    public init(response: SmtpResponse) {
        self.response = response
        self.rawLines = response.lines
        self.mailboxes = SmtpAddressQueryParser.parseMailboxes(from: response.lines)
    }

    public var enhancedStatusCodes: [SmtpEnhancedStatusCode] {
        response.enhancedStatusCodes
    }

    public var enhancedStatusCode: SmtpEnhancedStatusCode? {
        response.enhancedStatusCode
    }
}

public struct SmtpExpnResult: @unchecked Sendable {
    public let response: SmtpResponse
    public let mailboxes: [MailboxAddress]
    public let rawLines: [String]

    public init(response: SmtpResponse) {
        self.response = response
        self.rawLines = response.lines
        self.mailboxes = SmtpAddressQueryParser.parseMailboxes(from: response.lines)
    }

    public var enhancedStatusCodes: [SmtpEnhancedStatusCode] {
        response.enhancedStatusCodes
    }

    public var enhancedStatusCode: SmtpEnhancedStatusCode? {
        response.enhancedStatusCode
    }
}

public struct SmtpHelpResult: Sendable {
    public let response: SmtpResponse
    public let lines: [String]

    public init(response: SmtpResponse) {
        self.response = response
        self.lines = response.lines
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public var enhancedStatusCodes: [SmtpEnhancedStatusCode] {
        response.enhancedStatusCodes
    }

    public var enhancedStatusCode: SmtpEnhancedStatusCode? {
        response.enhancedStatusCode
    }
}

public enum SmtpAddressQueryParser {
    public static func parseMailboxes(from lines: [String]) -> [MailboxAddress] {
        var mailboxes: [MailboxAddress] = []
        var seen: Set<String> = []

        for line in lines {
            if let list = try? AddressParser.parseList(line) {
                addMailboxes(list.mailboxes, to: &mailboxes, seen: &seen)
                continue
            }
            if let mailbox = try? AddressParser.parseMailbox(line) {
                addMailboxes([mailbox], to: &mailboxes, seen: &seen)
                continue
            }
            if let angle = extractAngleAddress(from: line),
               let mailbox = try? AddressParser.parseMailbox(angle) {
                addMailboxes([mailbox], to: &mailboxes, seen: &seen)
                continue
            }
        }

        return mailboxes
    }

    private static func addMailboxes(_ items: [MailboxAddress], to output: inout [MailboxAddress], seen: inout Set<String>) {
        for mailbox in items {
            let key = mailbox.address.lowercased()
            if seen.insert(key).inserted {
                output.append(mailbox)
            }
        }
    }

    private static func extractAngleAddress(from line: String) -> String? {
        guard let start = line.firstIndex(of: "<") else { return nil }
        guard let end = line[start...].firstIndex(of: ">") else { return nil }
        let value = line[line.index(after: start)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
