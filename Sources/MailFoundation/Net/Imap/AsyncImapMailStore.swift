//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

//
// AsyncImapMailStore.swift
//
// Async IMAP mail store and folder wrappers.
//

/// An async/await IMAP mail store that provides access to mailboxes on an IMAP server.
///
/// The `AsyncImapMailStore` class is the async counterpart to `ImapMailStore`, providing
/// the same functionality using Swift's async/await concurrency model. It is implemented
/// as an actor for thread-safe access.
///
/// ## Overview
///
/// Before you can retrieve messages with the `AsyncImapMailStore`, you must first
/// call `connect()` and then authenticate with `authenticate(user:password:)`.
///
/// ## Usage Example
///
/// ```swift
/// // Create and connect to an IMAP server
/// let store = try AsyncImapMailStore.make(host: "imap.example.com", port: 993, backend: .tls)
/// try await store.connect()
///
/// // Authenticate
/// try await store.authenticate(user: "user@example.com", password: "secret")
///
/// // Open the inbox
/// let inbox = try await store.openInbox(access: .readOnly)
///
/// // Search for messages
/// let results = try await store.search(.all)
///
/// // Disconnect when done
/// await store.disconnect()
/// ```
///
/// ## Thread Safety
///
/// `AsyncImapMailStore` is an actor, providing automatic thread-safe access to its state.
/// All methods are async and can be called from any context.
///
/// ## See Also
///
/// - ``AsyncImapFolder``
/// - ``ImapMailStore``
/// - ``AsyncImapSession``
@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapMailStore: AsyncMailStore {
    /// The type of folder used by this mail store.
    public typealias FolderType = AsyncImapFolder

    private let session: AsyncImapSession
    private var selectedFolderStorage: AsyncImapFolder?
    private var selectedAccessStorage: FolderAccess?

    /// The capabilities advertised by the server.
    public var capabilities: ImapCapabilities? {
        get async {
            await session.capabilities
        }
    }

    /// The last known namespace response, if queried.
    public var namespaces: ImapNamespaceResponse? {
        get async {
            await session.namespaces
        }
    }

    /// Mailboxes marked as special-use by the server.
    public var specialUseMailboxes: [ImapMailbox] {
        get async {
            await session.specialUseMailboxes
        }
    }

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

    /// Creates a new async IMAP mail store connected to the specified host.
    ///
    /// This factory method creates the underlying transport and initializes the mail store.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the IMAP server.
    ///   - port: The port number (typically 143 for IMAP or 993 for IMAPS).
    ///   - backend: The transport backend to use.
    ///   - timeoutMilliseconds: The timeout for network operations (default: 120000).
    /// - Returns: A configured `AsyncImapMailStore` instance.
    /// - Throws: An error if the transport cannot be created.
    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        timeoutMilliseconds: Int = defaultImapTimeoutMs
    ) throws -> AsyncImapMailStore {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncImapMailStore(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    /// Creates a new async IMAP mail store with proxy support.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the IMAP server.
    ///   - port: The port number.
    ///   - backend: The transport backend to use.
    ///   - proxy: The proxy settings for tunneling the connection.
    ///   - timeoutMilliseconds: The timeout for network operations.
    /// - Returns: A configured `AsyncImapMailStore` instance.
    /// - Throws: An error if the transport cannot be created.
    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        proxy: ProxySettings,
        timeoutMilliseconds: Int = defaultImapTimeoutMs
    ) async throws -> AsyncImapMailStore {
        let transport = try await AsyncTransportFactory.make(host: host, port: port, backend: backend, proxy: proxy)
        return AsyncImapMailStore(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    /// Initializes a new async IMAP mail store with the given transport.
    ///
    /// - Parameters:
    ///   - transport: The async transport to use for communication.
    ///   - timeoutMilliseconds: The timeout for network operations.
    public init(
        transport: AsyncTransport,
        timeoutMilliseconds: Int = defaultImapTimeoutMs
    ) {
        self.session = AsyncImapSession(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    /// Connects to the IMAP server and retrieves the server greeting.
    ///
    /// - Returns: The server's greeting response, or `nil` if none.
    /// - Throws: An error if the connection fails.
    @discardableResult
    public func connect() async throws -> ImapResponse? {
        try await session.connect()
    }

    /// Disconnects from the IMAP server.
    ///
    /// This method closes the connection and resets the selected folder state.
    public func disconnect() async {
        await session.disconnect()
        selectedFolderStorage = nil
        selectedAccessStorage = nil
    }

    /// Authenticates with the IMAP server using the LOGIN command.
    ///
    /// - Parameters:
    ///   - user: The username or email address.
    ///   - password: The password or app-specific password.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails.
    public func authenticate(user: String, password: String) async throws -> ImapResponse? {
        try await session.login(user: user, password: password)
    }

    /// Authenticates using SASL mechanism.
    ///
    /// - Parameter auth: The SASL authentication configuration.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails.
    public func authenticate(_ auth: ImapAuthentication) async throws -> ImapResponse? {
        try await session.authenticate(auth)
    }

    /// Authenticates using XOAUTH2 with an OAuth access token.
    ///
    /// This method is used for OAuth 2.0 authentication with services like Gmail
    /// and Outlook.com. You must obtain an access token from the OAuth provider
    /// before using this method.
    ///
    /// - Parameters:
    ///   - user: The username or email address.
    ///   - accessToken: The OAuth 2.0 access token.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try AsyncImapMailStore.make(host: "imap.gmail.com", port: 993, backend: .network)
    /// try await store.connect()
    /// try await store.authenticateXoauth2(user: "user@gmail.com", accessToken: "ya29.a0AfH6SMB...")
    /// ```
    public func authenticateXoauth2(user: String, accessToken: String) async throws -> ImapResponse? {
        try await session.authenticateXoauth2(user: user, accessToken: accessToken)
    }

    /// Authenticates using SASL with automatic mechanism selection.
    public func authenticateSasl(
        user: String,
        password: String,
        mechanisms: [String]? = nil,
        host: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) async throws -> ImapResponse? {
        try await session.authenticateSasl(
            user: user,
            password: password,
            mechanisms: mechanisms,
            host: host,
            channelBinding: channelBinding
        )
    }

    /// The current state of the mail service.
    public var state: MailServiceState {
        get async {
            await session.state
        }
    }

    /// Whether the client is currently connected.
    public var isConnected: Bool {
        get async {
            await session.isConnected
        }
    }

    /// Whether the client is authenticated.
    public var isAuthenticated: Bool {
        get async {
            await session.isAuthenticated
        }
    }

    /// The currently selected folder, if any.
    public var selectedFolder: AsyncImapFolder? {
        get async {
            selectedFolderStorage
        }
    }

    /// The access mode of the currently selected folder.
    public var selectedAccess: FolderAccess? {
        get async {
            selectedAccessStorage
        }
    }

    /// Gets a folder reference by path without opening it.
    ///
    /// - Parameter path: The full path to the folder.
    /// - Returns: An `AsyncImapFolder` reference.
    public func getFolder(_ path: String) async throws -> AsyncImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return AsyncImapFolder(session: session, mailbox: mailbox, store: self)
    }

    /// Lists folders matching the specified pattern.
    ///
    /// - Parameters:
    ///   - reference: The reference name (typically empty string).
    ///   - pattern: The pattern to match.
    ///   - subscribedOnly: If `true`, only returns subscribed folders.
    /// - Returns: An array of `AsyncImapFolder` objects.
    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) async throws -> [AsyncImapFolder] {
        let mailboxes = subscribedOnly
            ? try await session.lsub(reference: reference, mailbox: pattern)
            : try await session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { AsyncImapFolder(session: session, mailbox: $0, store: self) }
    }

    /// Opens a folder with the specified access mode.
    ///
    /// - Parameters:
    ///   - path: The full path to the folder.
    ///   - access: The desired access mode.
    /// - Returns: The opened `AsyncImapFolder`.
    public func openFolder(_ path: String, access: FolderAccess) async throws -> AsyncImapFolder {
        let folder = try await getFolder(path)
        _ = try await folder.open(access)
        return folder
    }

    /// Opens the INBOX folder with the specified access mode.
    ///
    /// - Parameter access: The desired access mode.
    /// - Returns: The opened INBOX folder.
    public func openInbox(access: FolderAccess) async throws -> AsyncImapFolder {
        try await openFolder("INBOX", access: access)
    }

    /// Opens the specified folder with the given access mode.
    ///
    /// - Parameters:
    ///   - folder: The folder to open.
    ///   - access: The desired access mode.
    public func openFolder(_ folder: AsyncImapFolder, access: FolderAccess) async throws {
        _ = try await folder.open(access)
    }

    /// Closes the currently selected folder.
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

    /// Creates a new folder with the specified path.
    ///
    /// - Parameters:
    ///   - path: The full path for the new folder.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The created `AsyncImapFolder`.
    public func createFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        let folder = try await getFolder(path)
        _ = try await folder.create(maxEmptyReads: maxEmptyReads)
        return folder
    }

    /// Creates the specified folder on the server.
    ///
    /// - Parameters:
    ///   - folder: The folder to create.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The created `AsyncImapFolder`.
    public func createFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        _ = try await folder.create(maxEmptyReads: maxEmptyReads)
        return folder
    }

    /// Deletes a folder by path.
    ///
    /// - Parameters:
    ///   - path: The full path of the folder to delete.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
    public func deleteFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        if let selectedFolderStorage, selectedFolderStorage.mailbox.name == path {
            return try await selectedFolderStorage.delete(maxEmptyReads: maxEmptyReads)
        }
        let folder = try await getFolder(path)
        return try await folder.delete(maxEmptyReads: maxEmptyReads)
    }

    /// Deletes the specified folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to delete.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
    public func deleteFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await folder.delete(maxEmptyReads: maxEmptyReads)
    }

    /// Renames a folder.
    ///
    /// - Parameters:
    ///   - path: The current path of the folder.
    ///   - newName: The new name for the folder.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The renamed `AsyncImapFolder`.
    public func renameFolder(_ path: String, to newName: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        if let selectedFolderStorage, selectedFolderStorage.mailbox.name == path {
            return try await selectedFolderStorage.rename(to: newName, maxEmptyReads: maxEmptyReads)
        }
        let folder = try await getFolder(path)
        return try await folder.rename(to: newName, maxEmptyReads: maxEmptyReads)
    }

    /// Renames the specified folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to rename.
    ///   - newName: The new name for the folder.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The renamed `AsyncImapFolder`.
    public func renameFolder(_ folder: AsyncImapFolder, to newName: String, maxEmptyReads: Int = 10) async throws -> AsyncImapFolder {
        try await folder.rename(to: newName, maxEmptyReads: maxEmptyReads)
    }

    /// Subscribes to a folder.
    ///
    /// - Parameters:
    ///   - path: The full path of the folder to subscribe to.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
    public func subscribeFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let folder = try await getFolder(path)
        return try await folder.subscribe(maxEmptyReads: maxEmptyReads)
    }

    /// Subscribes to the specified folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to subscribe to.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
    public func subscribeFolder(_ folder: AsyncImapFolder, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await folder.subscribe(maxEmptyReads: maxEmptyReads)
    }

    /// Unsubscribes from a folder.
    ///
    /// - Parameters:
    ///   - path: The full path of the folder to unsubscribe from.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
    public func unsubscribeFolder(_ path: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let folder = try await getFolder(path)
        return try await folder.unsubscribe(maxEmptyReads: maxEmptyReads)
    }

    /// Unsubscribes from the specified folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to unsubscribe from.
    ///   - maxEmptyReads: Maximum read attempts for the response.
    /// - Returns: The server's response.
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

    public func id(_ parameters: [String: String?]? = nil, maxEmptyReads: Int = 10) async throws -> ImapIdResponse? {
        try await session.id(parameters, maxEmptyReads: maxEmptyReads)
    }

    public func namespace(maxEmptyReads: Int = 10) async throws -> ImapNamespaceResponse? {
        try await session.namespace(maxEmptyReads: maxEmptyReads)
    }

    public func getQuota(_ root: String, maxEmptyReads: Int = 10) async throws -> ImapQuotaResponse? {
        try await session.getQuota(root, maxEmptyReads: maxEmptyReads)
    }

    public func getQuotaRoot(_ mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapQuotaRootResult {
        try await session.getQuotaRoot(mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func getAcl(_ mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapAclResponse? {
        try await session.getAcl(mailbox: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func setAcl(
        _ mailbox: String,
        identifier: String,
        rights: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setAcl(
            mailbox: mailbox,
            identifier: identifier,
            rights: rights,
            maxEmptyReads: maxEmptyReads
        )
    }

    public func listRights(
        _ mailbox: String,
        identifier: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapListRightsResponse? {
        try await session.listRights(mailbox: mailbox, identifier: identifier, maxEmptyReads: maxEmptyReads)
    }

    public func myRights(_ mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapMyRightsResponse? {
        try await session.myRights(mailbox: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func getMetadata(
        _ mailbox: String,
        options: ImapMetadataOptions? = nil,
        entries: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapMetadataResponse? {
        try await session.getMetadata(mailbox: mailbox, options: options, entries: entries, maxEmptyReads: maxEmptyReads)
    }

    public func setMetadata(
        _ mailbox: String,
        entries: [ImapMetadataEntry],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setMetadata(mailbox: mailbox, entries: entries, maxEmptyReads: maxEmptyReads)
    }

    public func getAnnotation(
        _ mailbox: String,
        entries: [String],
        attributes: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapAnnotationResult? {
        try await session.getAnnotation(
            mailbox: mailbox,
            entries: entries,
            attributes: attributes,
            maxEmptyReads: maxEmptyReads
        )
    }

    public func setAnnotation(
        _ mailbox: String,
        entry: String,
        attributes: [ImapAnnotationAttribute],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setAnnotation(
            mailbox: mailbox,
            entry: entry,
            attributes: attributes,
            maxEmptyReads: maxEmptyReads
        )
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

    public func getQuotaRoot(maxEmptyReads: Int = 10) async throws -> ImapQuotaRootResult {
        let folder = try requireSelectedFolder()
        return try await folder.getQuotaRoot(maxEmptyReads: maxEmptyReads)
    }

    public func getAcl(maxEmptyReads: Int = 10) async throws -> ImapAclResponse? {
        let folder = try requireSelectedFolder()
        return try await folder.getAcl(maxEmptyReads: maxEmptyReads)
    }

    public func setAcl(
        identifier: String,
        rights: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        let folder = try requireSelectedFolder()
        return try await folder.setAcl(identifier: identifier, rights: rights, maxEmptyReads: maxEmptyReads)
    }

    public func listRights(identifier: String, maxEmptyReads: Int = 10) async throws -> ImapListRightsResponse? {
        let folder = try requireSelectedFolder()
        return try await folder.listRights(identifier: identifier, maxEmptyReads: maxEmptyReads)
    }

    public func myRights(maxEmptyReads: Int = 10) async throws -> ImapMyRightsResponse? {
        let folder = try requireSelectedFolder()
        return try await folder.myRights(maxEmptyReads: maxEmptyReads)
    }

    public func getMetadata(
        options: ImapMetadataOptions? = nil,
        entries: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapMetadataResponse? {
        let folder = try requireSelectedFolder()
        return try await folder.getMetadata(options: options, entries: entries, maxEmptyReads: maxEmptyReads)
    }

    public func setMetadata(
        entries: [ImapMetadataEntry],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        let folder = try requireSelectedFolder()
        return try await folder.setMetadata(entries: entries, maxEmptyReads: maxEmptyReads)
    }

    public func getAnnotation(
        entries: [String],
        attributes: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapAnnotationResult? {
        let folder = try requireSelectedFolder()
        return try await folder.getAnnotation(entries: entries, attributes: attributes, maxEmptyReads: maxEmptyReads)
    }

    public func setAnnotation(
        entry: String,
        attributes: [ImapAnnotationAttribute],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        let folder = try requireSelectedFolder()
        return try await folder.setAnnotation(entry: entry, attributes: attributes, maxEmptyReads: maxEmptyReads)
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

/// Represents an async IMAP folder (mailbox) on the server.
///
/// `AsyncImapFolder` is the async counterpart to `ImapFolder`, providing the same
/// folder operations using Swift's async/await concurrency model. It is implemented
/// as an actor for thread-safe access.
///
/// ## Overview
///
/// IMAP folders correspond to mailboxes on the server. Each folder has a name,
/// attributes, and may contain messages. The folder must be opened before you can
/// search, fetch, or modify messages.
///
/// ## Usage Example
///
/// ```swift
/// // Get and open a folder
/// let folder = try await store.getFolder("Archive/2024")
/// try await folder.open(.readOnly)
///
/// // Search for messages
/// let results = try await folder.search(.unseen)
///
/// // Close the folder
/// try await folder.close()
/// ```
///
/// ## Thread Safety
///
/// `AsyncImapFolder` is an actor, providing automatic thread-safe access to its state.
///
/// ## See Also
///
/// - ``AsyncImapMailStore``
/// - ``ImapMailbox``
/// - ``ImapFolder``
@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapFolder: AsyncMailFolder {
    /// The underlying mailbox information including name and attributes.
    public nonisolated let mailbox: ImapMailbox

    /// The decoded full name of the folder.
    public nonisolated let fullName: String

    /// The short name of the folder (last component of the path).
    public nonisolated let name: String

    private let session: AsyncImapSession
    private weak var store: AsyncImapMailStore?
    private var access: FolderAccess?

    /// Initializes a new async IMAP folder.
    ///
    /// - Parameters:
    ///   - session: The async IMAP session to use for commands.
    ///   - mailbox: The mailbox information.
    ///   - store: The parent mail store (held weakly).
    public init(session: AsyncImapSession, mailbox: ImapMailbox, store: AsyncImapMailStore?) {
        self.session = session
        self.mailbox = mailbox
        self.store = store
        self.fullName = mailbox.decodedName
        self.name = MailFolderBase.computeName(mailbox.decodedName, delimiter: mailbox.delimiter)
    }

    /// Whether the folder is currently open.
    public var isOpen: Bool {
        access != nil
    }

    /// Opens the folder with the specified access mode.
    ///
    /// - Parameter access: The desired access mode.
    /// - Returns: The server's response.
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

    public func getQuotaRoot(maxEmptyReads: Int = 10) async throws -> ImapQuotaRootResult {
        try await session.getQuotaRoot(mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func getAcl(maxEmptyReads: Int = 10) async throws -> ImapAclResponse? {
        try await session.getAcl(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func setAcl(
        identifier: String,
        rights: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setAcl(
            mailbox: mailbox.name,
            identifier: identifier,
            rights: rights,
            maxEmptyReads: maxEmptyReads
        )
    }

    public func listRights(identifier: String, maxEmptyReads: Int = 10) async throws -> ImapListRightsResponse? {
        try await session.listRights(mailbox: mailbox.name, identifier: identifier, maxEmptyReads: maxEmptyReads)
    }

    public func myRights(maxEmptyReads: Int = 10) async throws -> ImapMyRightsResponse? {
        try await session.myRights(mailbox: mailbox.name, maxEmptyReads: maxEmptyReads)
    }

    public func getMetadata(
        options: ImapMetadataOptions? = nil,
        entries: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapMetadataResponse? {
        try await session.getMetadata(
            mailbox: mailbox.name,
            options: options,
            entries: entries,
            maxEmptyReads: maxEmptyReads
        )
    }

    public func setMetadata(
        entries: [ImapMetadataEntry],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setMetadata(mailbox: mailbox.name, entries: entries, maxEmptyReads: maxEmptyReads)
    }

    public func getAnnotation(
        entries: [String],
        attributes: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapAnnotationResult? {
        try await session.getAnnotation(
            mailbox: mailbox.name,
            entries: entries,
            attributes: attributes,
            maxEmptyReads: maxEmptyReads
        )
    }

    public func setAnnotation(
        entry: String,
        attributes: [ImapAnnotationAttribute],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await session.setAnnotation(
            mailbox: mailbox.name,
            entry: entry,
            attributes: attributes,
            maxEmptyReads: maxEmptyReads
        )
    }

    internal func updateOpenState(_ access: FolderAccess?) async {
        self.access = access
    }
}
