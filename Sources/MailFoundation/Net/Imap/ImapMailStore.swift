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

    public func openInbox(access: FolderAccess) throws -> ImapFolder {
        try openFolder("INBOX", access: access)
    }

    public func openFolder(_ folder: ImapFolder, access: FolderAccess) throws {
        _ = try folder.open(access)
    }

    public func closeFolder() throws {
        guard let folder = selectedFolder else { return }
        _ = try folder.close()
    }

    private func requireSelectedFolder() throws -> ImapFolder {
        guard let folder = selectedFolder else {
            throw ImapMailStoreError.noSelectedFolder
        }
        return folder
    }

    public func createFolder(_ path: String) throws -> ImapFolder {
        let folder = try getFolder(path)
        _ = try folder.create()
        return folder
    }

    public func createFolder(_ folder: ImapFolder) throws -> ImapFolder {
        _ = try folder.create()
        return folder
    }

    public func deleteFolder(_ path: String) throws -> ImapResponse {
        if let selectedFolder, selectedFolder.mailbox.name == path {
            return try selectedFolder.delete()
        }
        let folder = try getFolder(path)
        return try folder.delete()
    }

    public func deleteFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.delete()
    }

    public func renameFolder(_ path: String, to newName: String) throws -> ImapFolder {
        if let selectedFolder, selectedFolder.mailbox.name == path {
            return try selectedFolder.rename(to: newName)
        }
        let folder = try getFolder(path)
        return try folder.rename(to: newName)
    }

    public func renameFolder(_ folder: ImapFolder, to newName: String) throws -> ImapFolder {
        try folder.rename(to: newName)
    }

    public func subscribeFolder(_ path: String) throws -> ImapResponse {
        let folder = try getFolder(path)
        return try folder.subscribe()
    }

    public func subscribeFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.subscribe()
    }

    public func unsubscribeFolder(_ path: String) throws -> ImapResponse {
        let folder = try getFolder(path)
        return try folder.unsubscribe()
    }

    public func unsubscribeFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.unsubscribe()
    }

    public func search(_ criteria: String) throws -> ImapSearchResponse {
        try requireSelectedFolder().search(criteria)
    }

    public func search(_ query: SearchQuery) throws -> ImapSearchResponse {
        try requireSelectedFolder().search(query)
    }

    public func uidSearch(_ criteria: String) throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSearch(criteria)
    }

    public func uidSearch(_ query: SearchQuery) throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSearch(query)
    }

    public func sort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try requireSelectedFolder().sort(orderBy, query: query, charset: charset)
    }

    public func uidSort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSort(orderBy, query: query, charset: charset)
    }

    public func copy(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().copy(set, to: mailbox)
    }

    public func copy(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().copy(set, to: mailbox)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().uidCopy(set, to: mailbox)
    }

    public func move(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().move(set, to: mailbox)
    }

    public func move(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().move(set, to: mailbox)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().uidMove(set, to: mailbox)
    }

    public func id(_ parameters: [String: String?]? = nil) throws -> ImapIdResponse? {
        try session.id(parameters)
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try requireSelectedFolder().fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(
        _ set: UniqueIdSet,
        request: FetchRequest,
        previewLength: Int = 512
    ) throws -> [MessageSummary] {
        try requireSelectedFolder().uidFetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func searchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().searchIdSet(criteria, validity: validity)
    }

    public func searchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().searchIdSet(query, validity: validity)
    }

    public func uidSearchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSearchIdSet(criteria, validity: validity)
    }

    public func uidSearchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSearchIdSet(query, validity: validity)
    }

    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try requireSelectedFolder().sortIdSet(orderBy, query: query, charset: charset, validity: validity)
    }

    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSortIdSet(orderBy, query: query, charset: charset, validity: validity)
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

    public func create() throws -> ImapResponse {
        try session.create(mailbox: mailbox.name)
    }

    public func delete() throws -> ImapResponse {
        let response = try session.delete(mailbox: mailbox.name)
        if store?.selectedFolder === self {
            updateOpenState(nil)
            store?.updateSelectedFolder(nil, access: nil)
        }
        return response
    }

    public func rename(to newName: String) throws -> ImapFolder {
        _ = try session.rename(mailbox: mailbox.name, newName: newName)
        let newMailbox = ImapMailbox(kind: mailbox.kind, name: newName, delimiter: mailbox.delimiter, attributes: mailbox.rawAttributes)
        let renamed = ImapFolder(session: session, mailbox: newMailbox, store: store)
        if let access = access, store?.selectedFolder === self {
            renamed.updateOpenState(access)
            store?.updateSelectedFolder(renamed, access: access)
        }
        return renamed
    }

    public func subscribe() throws -> ImapResponse {
        try session.subscribe(mailbox: mailbox.name)
    }

    public func unsubscribe() throws -> ImapResponse {
        try session.unsubscribe(mailbox: mailbox.name)
    }

    public func status(items: [String]) throws -> ImapStatusResponse {
        try session.status(mailbox: mailbox.name, items: items)
    }

    public func search(_ criteria: String) throws -> ImapSearchResponse {
        try session.search(criteria)
    }

    public func search(_ query: SearchQuery) throws -> ImapSearchResponse {
        try session.search(query)
    }

    public func searchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try search(criteria).idSet(validity: validity)
    }

    public func searchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try search(query).idSet(validity: validity)
    }

    public func uidSearch(_ criteria: String) throws -> ImapSearchResponse {
        try session.uidSearch(criteria)
    }

    public func uidSearch(_ query: SearchQuery) throws -> ImapSearchResponse {
        try session.uidSearch(query)
    }

    public func uidSearchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try uidSearch(criteria).idSet(validity: validity)
    }

    public func uidSearchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try uidSearch(query).idSet(validity: validity)
    }

    public func sort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try session.sort(orderBy, query: query, charset: charset)
    }

    public func uidSort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try session.uidSort(orderBy, query: query, charset: charset)
    }

    public func copy(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try session.copy(set, to: mailbox)
    }

    public func copy(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try session.copy(set, to: mailbox)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try session.uidCopy(set, to: mailbox)
    }

    public func move(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try session.move(set, to: mailbox)
    }

    public func move(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try session.move(set, to: mailbox)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try session.uidMove(set, to: mailbox)
    }

    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try sort(orderBy, query: query, charset: charset).idSet(validity: validity)
    }

    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try uidSort(orderBy, query: query, charset: charset).idSet(validity: validity)
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }
}
