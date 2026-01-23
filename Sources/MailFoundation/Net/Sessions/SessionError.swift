//
// SessionError.swift
//
// Common sync session errors.
//

public enum SessionError: Error, Sendable, Equatable {
    case timeout
    case transportWriteFailed
    case startTlsNotSupported
    case smtpError(code: Int, message: String)
    case pop3Error(message: String)
    case imapError(status: ImapResponseStatus?, text: String)
}
