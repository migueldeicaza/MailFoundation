//
// Pop3CommandError.swift
//
// POP3 command error wrapper (ported from MailKit semantics).
//

public struct Pop3CommandError: Error, Sendable, Equatable {
    public let message: String
    public let statusText: String

    public init(statusText: String, message: String? = nil) {
        self.statusText = statusText
        self.message = message ?? statusText
    }
}
