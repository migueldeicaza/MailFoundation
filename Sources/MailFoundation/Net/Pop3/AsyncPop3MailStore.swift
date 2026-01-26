//
// AsyncPop3MailStore.swift
//
// Async POP3 mail store and inbox folder wrapper.
//

import MimeFoundation

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3MailStore: AsyncMailStore {
    public typealias FolderType = AsyncPop3Folder

    private let session: AsyncPop3Session
    public nonisolated let inbox: AsyncPop3Folder
    private var selectedFolderStorage: AsyncPop3Folder?
    private var selectedAccessStorage: FolderAccess?

    /// The timeout for network operations in milliseconds.
    ///
    /// Default is 120000 (2 minutes), matching MailKit's default.
    /// Set to `Int.max` for no timeout.
    public var timeoutMilliseconds: Int {
        get async { await session.timeoutMilliseconds }
    }

    /// Sets the timeout for network operations.
    ///
    /// - Parameter milliseconds: The timeout in milliseconds
    public func setTimeout(milliseconds: Int) async {
        await session.setTimeoutMilliseconds(milliseconds)
    }

    public init(transport: AsyncTransport, timeoutMilliseconds: Int = defaultPop3TimeoutMs) {
        self.session = AsyncPop3Session(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
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

    public func authenticateSasl(
        user: String,
        password: String,
        capabilities: Pop3Capabilities? = nil,
        mechanisms: [String]? = nil
    ) async throws -> Pop3Response? {
        let response = try await session.authenticateSasl(
            user: user,
            password: password,
            capabilities: capabilities,
            mechanisms: mechanisms
        )
        await inbox.attachStore(self)
        _ = try await inbox.open(.readOnly)
        return response
    }

    public func authenticateCramMd5(user: String, password: String) async throws -> Pop3Response? {
        let response = try await session.authenticateCramMd5(user: user, password: password)
        await inbox.attachStore(self)
        _ = try await inbox.open(.readOnly)
        return response
    }

    public func authenticateXoauth2(user: String, accessToken: String) async throws -> Pop3Response? {
        let response = try await session.authenticateXoauth2(user: user, accessToken: accessToken)
        await inbox.attachStore(self)
        _ = try await inbox.open(.readOnly)
        return response
    }

    public func authenticateSasl(
        user: String,
        accessToken: String,
        capabilities: Pop3Capabilities? = nil,
        mechanisms: [String]? = nil
    ) async throws -> Pop3Response? {
        let response = try await session.authenticateSasl(
            user: user,
            accessToken: accessToken,
            capabilities: capabilities,
            mechanisms: mechanisms
        )
        await inbox.attachStore(self)
        _ = try await inbox.open(.readOnly)
        return response
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

    public func noop() async throws -> Pop3Response? {
        try await session.noop()
    }

    public func rset() async throws -> Pop3Response? {
        try await session.rset()
    }

    public func dele(_ index: Int) async throws -> Pop3Response? {
        try await session.dele(index)
    }

    public func last() async throws -> Int {
        try await session.last()
    }

    private func requireSelectedFolder() throws -> AsyncPop3Folder {
        guard let folder = selectedFolderStorage else {
            throw Pop3MailStoreError.noSelectedFolder
        }
        return folder
    }

    public func stat() async throws -> Pop3StatResponse? {
        try await requireSelectedFolder().stat()
    }

    public func list() async throws -> [Pop3ListItem] {
        try await requireSelectedFolder().list()
    }

    public func list(_ index: Int) async throws -> Pop3ListItem {
        try await requireSelectedFolder().list(index)
    }

    public func uidl() async throws -> [Pop3UidlItem] {
        try await requireSelectedFolder().uidl()
    }

    public func uidl(_ index: Int) async throws -> Pop3UidlItem {
        try await requireSelectedFolder().uidl(index)
    }

    public func retr(_ index: Int) async throws -> [String] {
        try await requireSelectedFolder().retr(index)
    }

    public func retrData(_ index: Int) async throws -> Pop3MessageData {
        try await requireSelectedFolder().retrData(index)
    }

    public func message(_ index: Int, options: ParserOptions = .default) async throws -> MimeMessage {
        try await requireSelectedFolder().message(index, options: options)
    }

    public func retrRaw(_ index: Int) async throws -> [UInt8] {
        try await requireSelectedFolder().retrRaw(index)
    }

    public func retrStream(
        _ index: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await requireSelectedFolder().retrStream(index, sink: sink)
    }

    public func top(_ index: Int, lines: Int) async throws -> [String] {
        try await requireSelectedFolder().top(index, lines: lines)
    }

    public func topData(_ index: Int, lines: Int) async throws -> Pop3MessageData {
        try await requireSelectedFolder().topData(index, lines: lines)
    }

    public func topHeaders(_ index: Int, lines: Int) async throws -> HeaderList {
        try await requireSelectedFolder().topHeaders(index, lines: lines)
    }

    public func topRaw(_ index: Int, lines: Int) async throws -> [UInt8] {
        try await requireSelectedFolder().topRaw(index, lines: lines)
    }

    public func topStream(
        _ index: Int,
        lines: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await requireSelectedFolder().topStream(index, lines: lines, sink: sink)
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

    public func noop() async throws -> Pop3Response? {
        try await session.noop()
    }

    public func rset() async throws -> Pop3Response? {
        try await session.rset()
    }

    public func dele(_ index: Int) async throws -> Pop3Response? {
        try await session.dele(index)
    }

    public func last() async throws -> Int {
        try await session.last()
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

    public func retrData(_ index: Int) async throws -> Pop3MessageData {
        try await session.retrData(index)
    }

    public func message(_ index: Int, options: ParserOptions = .default) async throws -> MimeMessage {
        try await retrData(index).message(options: options)
    }

    public func retrRaw(_ index: Int) async throws -> [UInt8] {
        try await session.retrRaw(index)
    }

    public func retrStream(
        _ index: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await session.retrStream(index, sink: sink)
    }

    public func top(_ index: Int, lines: Int) async throws -> [String] {
        try await session.top(index, lines: lines)
    }

    public func topData(_ index: Int, lines: Int) async throws -> Pop3MessageData {
        try await session.topData(index, lines: lines)
    }

    public func topHeaders(_ index: Int, lines: Int) async throws -> HeaderList {
        try await topData(index, lines: lines).parseHeaders()
    }

    public func topRaw(_ index: Int, lines: Int) async throws -> [UInt8] {
        try await session.topRaw(index, lines: lines)
    }

    public func topStream(
        _ index: Int,
        lines: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await session.topStream(index, lines: lines, sink: sink)
    }
}
