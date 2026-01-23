//
// SessionError.swift
//
// Common sync session errors.
//

public enum SessionError: Error, Sendable, Equatable {
    case timeout
    case transportWriteFailed
    case invalidState(expected: MailServiceState, actual: MailServiceState)
    case invalidImapState(expected: ImapSessionState, actual: ImapSessionState)
    case startTlsNotSupported
    case smtpError(code: Int, message: String)
    case pop3Error(message: String)
    case imapError(status: ImapResponseStatus?, text: String)
}
