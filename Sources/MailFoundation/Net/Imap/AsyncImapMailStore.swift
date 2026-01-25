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
    private var selectedFolderStorage: AsyncImapFolder?
    private var selectedAccessStorage: FolderAccess?

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
        selectedFolderStorage = nil
        selectedAccessStorage = nil
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

    public var selectedFolder: AsyncImapFolder? {
        get async {
            selectedFolderStorage
        }
    }

    public var selectedAccess: FolderAccess? {
        get async {
            selectedAccessStorage
        }
    }

    public func getFolder(_ path: String) async throws -> AsyncImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return AsyncImapFolder(session: session, mailbox: mailbox, store: self)
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) async throws -> [AsyncImapFolder] {
        let mailboxes = subscribedOnly
            ? try await session.lsub(reference: reference, mailbox: pattern)
            : try await session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { AsyncImapFolder(session: session, mailbox: $0, store: self) }
    }

    public func openFolder(_ path: String, access: FolderAccess) async throws -> AsyncImapFolder {
        let folder = try await getFolder(path)
        _ = try await folder.open(access)
        return folder
    }

    public func openInbox(access: FolderAccess) async throws -> AsyncImapFolder {
        try await openFolder("INBOX", access: access)
    }

    public func openFolder(_ folder: AsyncImapFolder, access: FolderAccess) async throws {
        _ = try await folder.open(access)
    }

    public func closeFolder() async throws {
        guard let folder = selectedFolderStorage else { return }
        _ = try await folder.close()
    }

    private func requireSelectedFolder() throws -> AsyncImapFolder {
        guard let folder = selectedFolderStorage else {
            throw ImapMailStoreError.noSelectedFolder
        }
        return folder
    }

    public func createFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        let folder = try await getFolder(path)
        _ = try await folder.create(maxEmptyReads: maxEmptyReads)
        return folder
    }

    public func createFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        _ = try await folder.create(maxEmptyReads: maxEmptyReads)
        return folder
    }

    public func deleteFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        if let selectedFolderStorage, selectedFolderStorage.mailbox.name == path {
            return try await selectedFolderStorage.delete(maxEmptyReads: maxEmptyReads)
        }
        let folder = try await getFolder(path)
        return try await folder.delete(maxEmptyReads: maxEmptyReads)
    }

    public func deleteFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await folder.delete(maxEmptyReads: maxEmptyReads)
    }

    public func renameFolder(_ path: String, to newName: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        if let selectedFolderStorage, selectedFolderStorage.mailbox.name == path {
            return try await selectedFolderStorage.rename(to: newName, maxEmptyReads: maxEmptyReads)
        }
        let folder = try await getFolder(path)
        return try await folder.rename(to: newName, maxEmptyReads: maxEmptyReads)
    }

    public func renameFolder(_ folder: AsyncImapFolder, to newName: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        try await folder.rename(to: newName, maxEmptyReads: maxEmptyReads)
    }

    public func subscribeFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let folder = try await getFolder(path)
        return try await folder.subscribe(maxEmptyReads: maxEmptyReads)
    }

    public func subscribeFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await folder.subscribe(maxEmptyReads: maxEmptyReads)
    }

    public func unsubscribeFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let folder = try await getFolder(path)
        return try await folder.unsubscribe(maxEmptyReads: maxEmptyReads)
    }

    public func unsubscribeFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await folder.unsubscribe(maxEmptyReads: maxEmptyReads)
    }

    public func search(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.search(criteria, maxEmptyReads: maxEmptyReads)
    }

    public func search(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.search(query, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearch(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.uidSearch(criteria, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearch(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.uidSearch(query, maxEmptyReads: maxEmptyReads)
    }

    public func sort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.sort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
    }

    public func uidSort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        let folder = try requireSelectedFolder()
        return try await folder.uidSort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
    }

    public func copy(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.copy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func copy(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.copy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.uidCopy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func move(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.move(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func move(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.move(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        let folder = try requireSelectedFolder()
        return try await folder.uidMove(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func fetchSummaries(
        _ set: String,
        request: FetchRequest,
        previewLength: Int = 512
    ) async throws -> [MessageSummary] {
        let folder = try requireSelectedFolder()
        return try await folder.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(
        _ set: UniqueIdSet,
        request: FetchRequest,
        previewLength: Int = 512
    ) async throws -> [MessageSummary] {
        let folder = try requireSelectedFolder()
        return try await folder.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func searchIdSet(
        _ criteria: String,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.searchIdSet(criteria, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    public func searchIdSet(
        _ query: SearchQuery,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.searchIdSet(query, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearchIdSet(
        _ criteria: String,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.uidSearchIdSet(criteria, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearchIdSet(
        _ query: SearchQuery,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.uidSearchIdSet(query, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.sortIdSet(orderBy, query: query, charset: charset, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        let folder = try requireSelectedFolder()
        return try await folder.uidSortIdSet(orderBy, query: query, charset: charset, validity: validity, maxEmptyReads: maxEmptyReads)
    }

    internal func updateSelectedFolder(_ folder: AsyncImapFolder?, access: FolderAccess?) {
        selectedFolderStorage = folder
        selectedAccessStorage = access
    }
}

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapFolder: AsyncMailFolder {
    public nonisolated let mailbox: ImapMailbox
    public nonisolated let fullName: String
    public nonisolated let name: String

    private let session: AsyncImapSession
    private weak var store: AsyncImapMailStore?
    private var access: FolderAccess?

    public init(session: AsyncImapSession, mailbox: ImapMailbox, store: AsyncImapMailStore?) {
        self.session = session
        self.mailbox = mailbox
        self.store = store
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
        if let store {
            await store.updateSelectedFolder(self, access: access)
        }
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
        if let store {
            await store.updateSelectedFolder(nil, access: nil)
        }
        return response
    }

    public func create(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await session.create(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func delete(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let response = try await session.delete(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
        if let store {
            let selected = await store.selectedFolder
            if selected === self {
                access = nil
                await store.updateSelectedFolder(nil, access: nil)
            }
        }
        return response
    }

    public func rename(to newName: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        _ = try await session.rename(mailbox: mailbox.name, newName: newName, maxEmptyReads: maxEmptyReads)
        let newMailbox = ImapMailbox(kind: mailbox.kind, name: newName, delimiter: mailbox.delimiter, attributes: mailbox.rawAttributes)
        let renamed = AsyncImapFolder(session: session, mailbox: newMailbox, store: store)
        if let store {
            let selected = await store.selectedFolder
            if selected === self, let access {
                await renamed.updateOpenState(access)
                await store.updateSelectedFolder(renamed, access: access)
            }
        }
        return renamed
    }

    public func subscribe(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await session.subscribe(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func unsubscribe(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await session.unsubscribe(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func expunge(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await session.expunge(maxEmptyReads: maxEmptyReads)
    }

    public func status(items: [String], maxEmptyReads: Int = 10) async throws -> ImapStatusResponse {
        try await session.status(mailbox: mailbox.name, items: items, maxEmptyReads: maxEmptyReads)
    }

    public func search(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await session.search(criteria, maxEmptyReads: maxEmptyReads)
    }

    public func search(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await session.search(query, maxEmptyReads: maxEmptyReads)
    }

    public func searchIdSet(
        _ criteria: String,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await search(criteria, maxEmptyReads: maxEmptyReads).idSet(validity: validity)
    }

    public func searchIdSet(
        _ query: SearchQuery,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await search(query, maxEmptyReads: maxEmptyReads).idSet(validity: validity)
    }

    public func uidSearch(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await session.uidSearch(criteria, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearch(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await session.uidSearch(query, maxEmptyReads: maxEmptyReads)
    }

    public func uidSearchIdSet(
        _ criteria: String,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await uidSearch(criteria, maxEmptyReads: maxEmptyReads).idSet(validity: validity)
    }

    public func uidSearchIdSet(
        _ query: SearchQuery,
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await uidSearch(query, maxEmptyReads: maxEmptyReads).idSet(validity: validity)
    }

    public func sort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        try await session.sort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
    }

    public func uidSort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        try await session.uidSort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
    }

    public func copy(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.copy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func copy(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.copy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.uidCopy(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func move(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.move(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func move(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.move(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await session.uidMove(set, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await sort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
            .idSet(validity: validity)
    }

    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0,
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchIdSet {
        try await uidSort(orderBy, query: query, charset: charset, maxEmptyReads: maxEmptyReads)
            .idSet(validity: validity)
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) async throws -> [MessageSummary] {
        try await session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }

    internal func updateOpenState(_ access: FolderAccess?) async {
        self.access = access
    }
}
