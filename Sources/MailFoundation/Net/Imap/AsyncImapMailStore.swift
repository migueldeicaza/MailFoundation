//
// AsyncImapMailStore.swift
//
// Async IMAP mail store and folder wrappers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapMailStore: AsyncMailStore {
    public typealias FolderType = AsyncImapFolder

    private let session: AsyncImapSession
    public let protocolLogger: ProtocolLoggerType

    public init(transport: AsyncTransport, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.protocolLogger = protocolLogger
        self.session = AsyncImapSession(transport: transport)
    }

    @discardableResult
    public func connect() async throws -> ImapResponse? {
        try await session.connect()
    }

    public func disconnect() async {
        await session.disconnect()
    }

    public func authenticate(user: String, password: String) async throws -> ImapResponse? {
        try await session.login(user: user, password: password)
    }

    public var state: MailServiceState {
        get async {
            await session.state
        }
    }

    public var isConnected: Bool {
        get async {
            await session.isConnected
        }
    }

    public var isAuthenticated: Bool {
        get async {
            await session.isAuthenticated
        }
    }

    public func getFolder(_ path: String) async throws -> AsyncImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return AsyncImapFolder(session: session, mailbox: mailbox)
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) async throws -> [AsyncImapFolder] {
        let mailboxes = subscribedOnly
            ? try await session.lsub(reference: reference, mailbox: pattern)
            : try await session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { AsyncImapFolder(session: session, mailbox: $0) }
    }
}

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapFolder: AsyncMailFolder {
    public nonisolated let mailbox: ImapMailbox
    public nonisolated let fullName: String
    public nonisolated let name: String

    private let session: AsyncImapSession
    private var access: FolderAccess?

    public init(session: AsyncImapSession, mailbox: ImapMailbox) {
        self.session = session
        self.mailbox = mailbox
        self.fullName = mailbox.decodedName
        self.name = MailFolderBase.computeName(mailbox.decodedName, delimiter: mailbox.delimiter)
    }

    public var isOpen: Bool {
        access != nil
    }

    public func open(_ access: FolderAccess) async throws -> ImapResponse? {
        let response: ImapResponse?
        switch access {
        case .readOnly:
            response = try await session.examine(mailbox: mailbox.name)
        case .readWrite:
            response = try await session.select(mailbox: mailbox.name)
        }
        self.access = access
        return response
    }

    public func openReadOnly() async throws -> ImapResponse? {
        try await open(.readOnly)
    }

    public func openReadWrite() async throws -> ImapResponse? {
        try await open(.readWrite)
    }

    public func close() async throws -> ImapResponse? {
        let response = try await session.close()
        access = nil
        return response
    }

    public func expunge(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await session.expunge(maxEmptyReads: maxEmptyReads)
    }

    public func status(items: [String], maxEmptyReads: Int = 10) async throws -> ImapStatusResponse {
        try await session.status(mailbox: mailbox.name, items: items, maxEmptyReads: maxEmptyReads)
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }
}
