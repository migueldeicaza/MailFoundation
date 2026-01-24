//
// Pop3MailStore.swift
//
// POP3 mail store and inbox folder wrapper.
//

import SwiftMimeKit

public enum Pop3FolderError: Error, Sendable {
    case unsupportedFolder
    case unsupportedAccess
}

public final class Pop3MailStore: MailServiceBase<Pop3Response>, MailStore {
    public typealias FolderType = Pop3Folder

    private let session: Pop3Session
    public private(set) var inbox: Pop3Folder
    public private(set) var selectedFolder: Pop3Folder?
    public private(set) var selectedAccess: FolderAccess?

    public override var protocolName: String { "POP3" }

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.session = Pop3Session(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
        self.inbox = Pop3Folder(session: self.session, store: nil)
        super.init(protocolLogger: protocolLogger)
        self.inbox.store = self
    }

    @discardableResult
    public override func connect() throws -> Pop3Response {
        let response = try session.connect()
        updateState(.connected)
        return response
    }

    public func authenticate(user: String, password: String) throws -> (user: Pop3Response, pass: Pop3Response) {
        let responses = try session.authenticate(user: user, password: password)
        updateState(.authenticated)
        _ = try inbox.open(.readOnly)
        return responses
    }

    public override func disconnect() {
        inbox.close()
        session.disconnect()
        updateSelectedFolder(nil, access: nil)
        super.disconnect()
    }

    public func getFolder(_ path: String) throws -> Pop3Folder {
        guard path.caseInsensitiveCompare("INBOX") == .orderedSame else {
            throw Pop3FolderError.unsupportedFolder
        }
        return inbox
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) throws -> [Pop3Folder] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "%" || trimmed.caseInsensitiveCompare("INBOX") == .orderedSame {
            return [inbox]
        }
        return []
    }

    public func openInbox(access: FolderAccess = .readOnly) throws -> Pop3Folder {
        _ = try inbox.open(access)
        return inbox
    }

    internal func updateSelectedFolder(_ folder: Pop3Folder?, access: FolderAccess?) {
        selectedFolder = folder
        selectedAccess = access
    }
}

public final class Pop3Folder: MailFolderBase {
    fileprivate weak var store: Pop3MailStore?
    private let session: Pop3Session

    public init(session: Pop3Session, store: Pop3MailStore?) {
        self.session = session
        self.store = store
        super.init(fullName: "INBOX", delimiter: nil)
    }

    public func open(_ access: FolderAccess) throws -> Pop3Response? {
        guard access == .readOnly else {
            throw Pop3FolderError.unsupportedAccess
        }
        updateOpenState(access)
        store?.updateSelectedFolder(self, access: access)
        return nil
    }

    public func close() {
        updateOpenState(nil)
        store?.updateSelectedFolder(nil, access: nil)
    }

    public func stat() throws -> Pop3StatResponse {
        try session.stat()
    }

    public func list() throws -> [Pop3ListItem] {
        try session.list()
    }

    public func list(_ index: Int) throws -> Pop3ListItem {
        try session.list(index)
    }

    public func uidl() throws -> [Pop3UidlItem] {
        try session.uidl()
    }

    public func uidl(_ index: Int) throws -> Pop3UidlItem {
        try session.uidl(index)
    }

    public func retr(_ index: Int) throws -> [String] {
        try session.retr(index)
    }

    public func retrData(_ index: Int) throws -> Pop3MessageData {
        try session.retrData(index)
    }

    public func message(_ index: Int, options: ParserOptions = .default) throws -> MimeMessage {
        try retrData(index).message(options: options)
    }

    public func retrRaw(_ index: Int) throws -> [UInt8] {
        try session.retrRaw(index)
    }

    public func retrStream(_ index: Int, sink: ([UInt8]) throws -> Void) throws {
        try session.retrStream(index, sink: sink)
    }

    public func top(_ index: Int, lines: Int) throws -> [String] {
        try session.top(index, lines: lines)
    }

    public func topData(_ index: Int, lines: Int) throws -> Pop3MessageData {
        try session.topData(index, lines: lines)
    }

    public func topHeaders(_ index: Int, lines: Int) throws -> HeaderList {
        try topData(index, lines: lines).parseHeaders()
    }

    public func topRaw(_ index: Int, lines: Int) throws -> [UInt8] {
        try session.topRaw(index, lines: lines)
    }

    public func topStream(_ index: Int, lines: Int, sink: ([UInt8]) throws -> Void) throws {
        try session.topStream(index, lines: lines, sink: sink)
    }
}
