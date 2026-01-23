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

    public init(session: AsyncImapSession, mailbox: ImapMailbox) {
        self.session = session
        self.mailbox = mailbox
        self.fullName = mailbox.decodedName
        if let delimiter = mailbox.delimiter, let last = mailbox.decodedName.split(separator: Character(delimiter)).last {
            self.name = String(last)
        } else {
            self.name = mailbox.decodedName
        }
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }
}
