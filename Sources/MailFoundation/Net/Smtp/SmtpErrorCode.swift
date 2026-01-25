//
// SmtpErrorCode.swift
//
// SMTP command error codes (ported from MailKit).
//

public enum SmtpErrorCode: Sendable, Equatable {
    case messageNotAccepted
    case senderNotAccepted
    case recipientNotAccepted
    case unexpectedStatusCode
}
