//
// AsyncPop3MailStore.swift
//
// Async POP3 mail store and inbox folder wrapper.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3MailStore: AsyncMailStore {
    public typealias FolderType = AsyncPop3Folder

    private let session: AsyncPop3Session
    public nonisolated let inbox: AsyncPop3Folder
    private var selectedFolderStorage: AsyncPop3Folder?
    private var selectedAccessStorage: FolderAccess?

    public init(transport: AsyncTransport) {
        self.session = AsyncPop3Session(transport: transport)
        let folder = AsyncPop3Folder(session: session, store: nil)
        self.inbox = folder
        Task { await folder.attachStore(self) }
    }

    @discardableResult
    public func connect() async throws -> Pop3Response? {
        try await session.connect()
    }

    public func disconnect() async {
        await inbox.close()
        await session.disconnect()
        selectedFolderStorage = nil
        selectedAccessStorage = nil
    }

    public var state: MailServiceState {
        get async {
            await session.isAuthenticated ? .authenticated : (await session.isConnected ? .connected : .disconnected)
        }
    }

    public var isConnected: Bool {
        get async { await session.isConnected }
    }

    public var isAuthenticated: Bool {
        get async { await session.isAuthenticated }
    }

    public var selectedFolder: AsyncPop3Folder? {
        get async { selectedFolderStorage }
    }

    public var selectedAccess: FolderAccess? {
        get async { selectedAccessStorage }
    }

    public func authenticate(user: String, password: String) async throws -> (user: Pop3Response?, pass: Pop3Response?) {
        let responses = try await session.authenticate(user: user, password: password)
        await inbox.attachStore(self)
        _ = try await inbox.open(.readOnly)
        return responses
    }

    public func getFolder(_ path: String) async throws -> AsyncPop3Folder {
        guard path.caseInsensitiveCompare("INBOX") == .orderedSame else {
            throw Pop3FolderError.unsupportedFolder
        }
        return inbox
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) async throws -> [AsyncPop3Folder] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "%" || trimmed.caseInsensitiveCompare("INBOX") == .orderedSame {
            return [inbox]
        }
        return []
    }

    public func openInbox(access: FolderAccess = .readOnly) async throws -> AsyncPop3Folder {
        await inbox.attachStore(self)
        _ = try await inbox.open(access)
        return inbox
    }

    internal func updateSelectedFolder(_ folder: AsyncPop3Folder?, access: FolderAccess?) {
        selectedFolderStorage = folder
        selectedAccessStorage = access
    }
}

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3Folder: AsyncMailFolder {
    public nonisolated let fullName: String = "INBOX"
    public nonisolated let name: String = "INBOX"

    private let session: AsyncPop3Session
    private weak var store: AsyncPop3MailStore?
    private var access: FolderAccess?

    public init(session: AsyncPop3Session, store: AsyncPop3MailStore?) {
        self.session = session
        self.store = store
    }

    internal func attachStore(_ store: AsyncPop3MailStore) {
        self.store = store
    }

    public var isOpen: Bool {
        access != nil
    }

    public func open(_ access: FolderAccess) async throws -> Pop3Response? {
        guard access == .readOnly else {
            throw Pop3FolderError.unsupportedAccess
        }
        self.access = access
        if let store {
            await store.updateSelectedFolder(self, access: access)
        }
        return nil
    }

    public func close() async {
        access = nil
        if let store {
            await store.updateSelectedFolder(nil, access: nil)
        }
    }

    public func stat() async throws -> Pop3StatResponse? {
        try await session.stat()
    }

    public func list() async throws -> [Pop3ListItem] {
        try await session.list()
    }

    public func list(_ index: Int) async throws -> Pop3ListItem {
        try await session.list(index)
    }

    public func uidl() async throws -> [Pop3UidlItem] {
        try await session.uidl()
    }

    public func uidl(_ index: Int) async throws -> Pop3UidlItem {
        try await session.uidl(index)
    }

    public func retr(_ index: Int) async throws -> [String] {
        try await session.retr(index)
    }

    public func top(_ index: Int, lines: Int) async throws -> [String] {
        try await session.top(index, lines: lines)
    }
}
