//
// ImapMailStore.swift
//
// IMAP mail store and folder wrappers.
//

public final class ImapMailStore: MailServiceBase<ImapResponse>, MailStore {
    public typealias FolderType = ImapFolder

    private let session: ImapSession
    public private(set) var selectedFolder: ImapFolder?
    public private(set) var selectedAccess: FolderAccess?

    public override var protocolName: String { "IMAP" }

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.session = ImapSession(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
        super.init(protocolLogger: protocolLogger)
    }

    public init(session: ImapSession, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.session = session
        super.init(protocolLogger: protocolLogger)
    }

    @discardableResult
    public override func connect() throws -> ImapResponse {
        let response = try session.connect()
        updateState(.connected)
        return response
    }

    public func authenticate(user: String, password: String) throws -> ImapResponse {
        let response = try session.login(user: user, password: password)
        updateState(.authenticated)
        return response
    }

    public override func disconnect() {
        session.disconnect()
        updateSelectedFolder(nil, access: nil)
        super.disconnect()
    }

    public func getFolder(_ path: String) throws -> ImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return ImapFolder(session: session, mailbox: mailbox, store: self)
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) throws -> [ImapFolder] {
        let mailboxes = subscribedOnly
            ? try session.lsub(reference: reference, mailbox: pattern)
            : try session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { ImapFolder(session: session, mailbox: $0, store: self) }
    }

    public func openFolder(_ path: String, access: FolderAccess) throws -> ImapFolder {
        let folder = try getFolder(path)
        _ = try folder.open(access)
        return folder
    }

    public func openFolder(_ folder: ImapFolder, access: FolderAccess) throws {
        _ = try folder.open(access)
    }

    public func closeFolder() throws {
        guard let folder = selectedFolder else { return }
        _ = try folder.close()
    }

    internal func updateSelectedFolder(_ folder: ImapFolder?, access: FolderAccess?) {
        selectedFolder = folder
        selectedAccess = access
    }
}

public final class ImapFolder: MailFolderBase {
    public let mailbox: ImapMailbox

    private let session: ImapSession
    private weak var store: ImapMailStore?

    public init(session: ImapSession, mailbox: ImapMailbox, store: ImapMailStore?) {
        self.session = session
        self.mailbox = mailbox
        self.store = store
        super.init(fullName: mailbox.decodedName, delimiter: mailbox.delimiter)
    }

    public var rawName: String {
        mailbox.name
    }

    public func open(_ access: FolderAccess) throws -> ImapResponse {
        let response: ImapResponse
        switch access {
        case .readOnly:
            response = try session.examine(mailbox: mailbox.name)
        case .readWrite:
            response = try session.select(mailbox: mailbox.name)
        }
        updateOpenState(access)
        store?.updateSelectedFolder(self, access: access)
        return response
    }

    public func openReadOnly() throws -> ImapResponse {
        try open(.readOnly)
    }

    public func openReadWrite() throws -> ImapResponse {
        try open(.readWrite)
    }

    public func close() throws -> ImapResponse {
        let response = try session.close()
        updateOpenState(nil)
        store?.updateSelectedFolder(nil, access: nil)
        return response
    }

    public func expunge() throws -> ImapResponse {
        try session.expunge()
    }

    public func status(items: [String]) throws -> ImapStatusResponse {
        try session.status(mailbox: mailbox.name, items: items)
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }
}
