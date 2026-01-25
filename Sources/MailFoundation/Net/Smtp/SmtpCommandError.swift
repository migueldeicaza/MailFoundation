//
// SmtpCommandError.swift
//
// SMTP command error wrapper (ported from MailKit semantics).
//

import MimeFoundation

public struct SmtpCommandError: Error, Sendable, Equatable {
    public let errorCode: SmtpErrorCode
    public let statusCode: SmtpStatusCode
    public let mailboxAddress: String?
    public let mailbox: MailboxAddress?
    public let message: String
    public let responseLines: [String]
    public let enhancedStatusCode: SmtpEnhancedStatusCode?

    public init(
        errorCode: SmtpErrorCode,
        response: SmtpResponse,
        mailboxAddress: String? = nil
    ) {
        self.errorCode = errorCode
        self.statusCode = SmtpStatusCode(rawValue: response.code)
        self.mailboxAddress = mailboxAddress
        self.mailbox = mailboxAddress.flatMap { try? MailboxAddress(parsing: $0) }
        self.message = response.lines.joined(separator: " ")
        self.responseLines = response.lines
        self.enhancedStatusCode = response.enhancedStatusCode
    }
}
