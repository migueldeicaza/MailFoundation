//
// ImapCopyResult.swift
//
// IMAP COPY/MOVE result wrapper.
//

public struct ImapCopyResult: Sendable, Equatable {
    public let response: ImapResponse
    public let copyUid: ImapCopyUid?

    public init(response: ImapResponse, copyUid: ImapCopyUid? = nil) {
        self.response = response
        self.copyUid = copyUid
    }
}
