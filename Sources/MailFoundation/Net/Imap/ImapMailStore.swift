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
// ImapMailStore.swift
//
// IMAP mail store and folder wrappers.
//

/// An IMAP mail store that provides access to mailboxes on an IMAP server.
///
/// The `ImapMailStore` class is the main entry point for connecting to an IMAP server
/// and accessing mailboxes. It provides methods for authentication, folder management,
/// and message operations.
///
/// ## Overview
///
/// Before you can retrieve messages with the `ImapMailStore`, you must first
/// call `connect()` and then authenticate with `authenticate(user:password:)`.
///
/// ## Usage Example
///
/// ```swift
/// // Create and connect to an IMAP server
/// let store = try ImapMailStore.make(host: "imap.example.com", port: 993, backend: .ssl)
/// try store.connect()
///
/// // Authenticate
/// try store.authenticate(user: "user@example.com", password: "secret")
///
/// // Open the inbox
/// let inbox = try store.openInbox(access: .readOnly)
///
/// // Search for messages
/// let results = try store.search(.all)
///
/// // Disconnect when done
/// store.disconnect()
/// ```
///
/// ## Thread Safety
///
/// `ImapMailStore` is not thread-safe. If you need to access the same mailbox from
/// multiple threads, create separate `ImapMailStore` instances for each thread.
///
/// ## See Also
///
/// - ``ImapFolder``
/// - ``AsyncImapMailStore``
/// - ``ImapSession``
public final class ImapMailStore: MailServiceBase<ImapResponse>, MailStore {
    /// The type of folder used by this mail store.
    public typealias FolderType = ImapFolder

    private let session: ImapSession

    /// The currently selected folder, if any.
    ///
    /// This property is automatically updated when you call `openFolder(_:access:)`,
    /// `openInbox(access:)`, or `closeFolder()`.
    public private(set) var selectedFolder: ImapFolder?

    /// The access mode of the currently selected folder.
    ///
    /// Returns `.readOnly` if the folder was opened with `EXAMINE`, or `.readWrite`
    /// if opened with `SELECT`. Returns `nil` if no folder is selected.
    public private(set) var selectedAccess: FolderAccess?

    /// The capabilities advertised by the server.
    public var capabilities: ImapCapabilities? {
        session.capabilities
    }

    /// The last known namespace response, if queried.
    public var namespaces: ImapNamespaceResponse? {
        session.namespaces
    }

    /// Mailboxes marked as special-use by the server.
    public var specialUseMailboxes: [ImapMailbox] {
        session.specialUseMailboxes
    }

    /// The protocol name used for logging purposes.
    public override var protocolName: String { "IMAP" }

    /// Creates a new IMAP mail store connected to the specified host.
    ///
    /// This factory method creates the underlying transport and initializes the mail store.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the IMAP server.
    ///   - port: The port number (typically 143 for IMAP or 993 for IMAPS).
    ///   - backend: The transport backend to use (`.tcp` for plain, `.ssl` for encrypted).
    ///   - proxy: Optional proxy settings for connecting through a proxy server.
    ///   - protocolLogger: A logger for protocol-level debugging.
    ///   - maxReads: Maximum number of read attempts when waiting for responses.
    /// - Returns: A configured `ImapMailStore` instance.
    /// - Throws: An error if the transport cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Connect to Gmail's IMAP server
    /// let store = try ImapMailStore.make(
    ///     host: "imap.gmail.com",
    ///     port: 993,
    ///     backend: .ssl
    /// )
    /// ```
    public static func make(
        host: String,
        port: Int,
        backend: TransportBackend = .tcp,
        proxy: ProxySettings? = nil,
        protocolLogger: ProtocolLoggerType = NullProtocolLogger(),
        maxReads: Int = 10
    ) throws -> ImapMailStore {
        let transport = try TransportFactory.make(host: host, port: port, backend: backend, proxy: proxy)
        return ImapMailStore(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
    }

    /// Initializes a new IMAP mail store with the given transport.
    ///
    /// Use this initializer when you have already created a transport and want
    /// fine-grained control over the connection.
    ///
    /// - Parameters:
    ///   - transport: The transport to use for communication.
    ///   - protocolLogger: A logger for protocol-level debugging.
    ///   - maxReads: Maximum number of read attempts when waiting for responses.
    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.session = ImapSession(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
        super.init(protocolLogger: protocolLogger)
    }

    /// Initializes a new IMAP mail store with an existing session.
    ///
    /// Use this initializer when you have an existing `ImapSession` that you want
    /// to wrap in a mail store interface.
    ///
    /// - Parameters:
    ///   - session: The IMAP session to use.
    ///   - protocolLogger: A logger for protocol-level debugging.
    public init(session: ImapSession, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.session = session
        super.init(protocolLogger: protocolLogger)
    }

    /// Connects to the IMAP server and retrieves the server greeting.
    ///
    /// This method establishes the connection and waits for the server's greeting
    /// response. After connecting, you should authenticate using `authenticate(user:password:)`.
    ///
    /// - Returns: The server's greeting response containing capability information.
    /// - Throws: An error if the connection fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try ImapMailStore.make(host: "imap.example.com", port: 993, backend: .ssl)
    /// let greeting = try store.connect()
    /// print("Connected: \(greeting.text ?? "")")
    /// ```
    @discardableResult
    public override func connect() throws -> ImapResponse {
        let response = try session.connect()
        updateState(.connected)
        updateAuthenticationMechanisms(session.capabilities?.saslMechanisms() ?? [])
        return response
    }

    /// Authenticates with the IMAP server using the LOGIN command.
    ///
    /// After successfully authenticating, you can access mailboxes and messages.
    /// The LOGIN command sends credentials in plain text, so ensure you are using
    /// an encrypted connection (SSL/TLS) for security.
    ///
    /// - Parameters:
    ///   - user: The username or email address.
    ///   - password: The password or app-specific password.
    /// - Returns: The server's response to the LOGIN command.
    /// - Throws: An error if authentication fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try store.connect()
    /// try store.authenticate(user: "user@example.com", password: "secret")
    /// // Now you can access mailboxes
    /// ```
    public func authenticate(user: String, password: String) throws -> ImapResponse {
        let response = try session.login(user: user, password: password)
        updateState(.authenticated)
        updateAuthenticationMechanisms(session.capabilities?.saslMechanisms() ?? [])
        return response
    }

    /// Authenticates using SASL mechanism.
    ///
    /// - Parameter auth: The SASL authentication configuration.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails.
    public func authenticate(_ auth: ImapAuthentication) throws -> ImapResponse {
        let response = try session.authenticate(auth)
        updateState(.authenticated)
        updateAuthenticationMechanisms(session.capabilities?.saslMechanisms() ?? [])
        return response
    }

    /// Authenticates using SASL with automatic mechanism selection.
    public func authenticateSasl(
        user: String,
        password: String,
        mechanisms: [String]? = nil,
        host: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) throws -> ImapResponse {
        let response = try session.authenticateSasl(
            user: user,
            password: password,
            mechanisms: mechanisms,
            host: host,
            channelBinding: channelBinding
        )
        updateState(.authenticated)
        updateAuthenticationMechanisms(session.capabilities?.saslMechanisms() ?? [])
        return response
    }

    /// Authenticates using XOAUTH2 with an OAuth access token.
    public func authenticateXoauth2(user: String, accessToken: String) throws -> ImapResponse {
        let response = try session.authenticateXoauth2(user: user, accessToken: accessToken)
        updateState(.authenticated)
        updateAuthenticationMechanisms(session.capabilities?.saslMechanisms() ?? [])
        return response
    }

    /// Disconnects from the IMAP server.
    ///
    /// This method closes the connection and resets the selected folder state.
    /// It is safe to call this method even if no connection exists.
    public override func disconnect() {
        session.disconnect()
        updateSelectedFolder(nil, access: nil)
        super.disconnect()
    }

    /// Gets a folder reference by path without opening it.
    ///
    /// This method creates a folder reference without checking if the folder exists
    /// on the server. Use `getFolders(reference:pattern:)` to list available folders.
    ///
    /// - Parameter path: The full path to the folder (e.g., "INBOX", "Archive/2024").
    /// - Returns: An `ImapFolder` reference for the specified path.
    /// - Throws: An error if the folder object cannot be created.
    public func getFolder(_ path: String) throws -> ImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return ImapFolder(session: session, mailbox: mailbox, store: self)
    }

    /// Lists folders matching the specified pattern.
    ///
    /// This method uses the IMAP LIST or LSUB command to retrieve folder information
    /// from the server.
    ///
    /// - Parameters:
    ///   - reference: The reference name (typically empty string "" for root).
    ///   - pattern: The pattern to match (e.g., "*" for all folders, "%" for top-level only).
    ///   - subscribedOnly: If `true`, only returns subscribed folders (LSUB command).
    /// - Returns: An array of `ImapFolder` objects matching the pattern.
    /// - Throws: An error if the LIST/LSUB command fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // List all folders
    /// let allFolders = try store.getFolders(reference: "", pattern: "*")
    ///
    /// // List only top-level folders
    /// let topLevel = try store.getFolders(reference: "", pattern: "%")
    ///
    /// // List only subscribed folders
    /// let subscribed = try store.getFolders(reference: "", pattern: "*", subscribedOnly: true)
    /// ```
    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) throws -> [ImapFolder] {
        let mailboxes = subscribedOnly
            ? try session.lsub(reference: reference, mailbox: pattern)
            : try session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { ImapFolder(session: session, mailbox: $0, store: self) }
    }

    /// Opens a folder with the specified access mode.
    ///
    /// This method issues a SELECT (for read-write) or EXAMINE (for read-only) command.
    /// Only one folder can be selected at a time; opening a new folder automatically
    /// deselects the previous one.
    ///
    /// - Parameters:
    ///   - path: The full path to the folder.
    ///   - access: The desired access mode (`.readOnly` or `.readWrite`).
    /// - Returns: The opened `ImapFolder`.
    /// - Throws: An error if the folder cannot be opened.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let folder = try store.openFolder("Archive/2024", access: .readOnly)
    /// ```
    public func openFolder(_ path: String, access: FolderAccess) throws -> ImapFolder {
        let folder = try getFolder(path)
        _ = try folder.open(access)
        return folder
    }

    /// Opens the INBOX folder with the specified access mode.
    ///
    /// This is a convenience method equivalent to `openFolder("INBOX", access:)`.
    ///
    /// - Parameter access: The desired access mode (`.readOnly` or `.readWrite`).
    /// - Returns: The opened INBOX folder.
    /// - Throws: An error if the INBOX cannot be opened.
    public func openInbox(access: FolderAccess) throws -> ImapFolder {
        try openFolder("INBOX", access: access)
    }

    /// Opens the specified folder with the given access mode.
    ///
    /// - Parameters:
    ///   - folder: The folder to open.
    ///   - access: The desired access mode.
    /// - Throws: An error if the folder cannot be opened.
    public func openFolder(_ folder: ImapFolder, access: FolderAccess) throws {
        _ = try folder.open(access)
    }

    /// Closes the currently selected folder.
    ///
    /// This method issues a CLOSE command, which also expunges any messages
    /// marked for deletion if the folder was opened in read-write mode.
    ///
    /// - Throws: An error if the CLOSE command fails.
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

    /// Creates a new folder with the specified path.
    ///
    /// - Parameter path: The full path for the new folder.
    /// - Returns: The created `ImapFolder`.
    /// - Throws: An error if the folder cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let archive = try store.createFolder("Archive/2024")
    /// ```
    public func createFolder(_ path: String) throws -> ImapFolder {
        let folder = try getFolder(path)
        _ = try folder.create()
        return folder
    }

    /// Creates the specified folder on the server.
    ///
    /// - Parameter folder: The folder to create.
    /// - Returns: The created `ImapFolder`.
    /// - Throws: An error if the folder cannot be created.
    public func createFolder(_ folder: ImapFolder) throws -> ImapFolder {
        _ = try folder.create()
        return folder
    }

    /// Deletes a folder by path.
    ///
    /// - Parameter path: The full path of the folder to delete.
    /// - Returns: The server's response.
    /// - Throws: An error if the folder cannot be deleted.
    ///
    /// - Warning: This operation is irreversible and will delete all messages in the folder.
    public func deleteFolder(_ path: String) throws -> ImapResponse {
        if let selectedFolder, selectedFolder.mailbox.name == path {
            return try selectedFolder.delete()
        }
        let folder = try getFolder(path)
        return try folder.delete()
    }

    /// Deletes the specified folder.
    ///
    /// - Parameter folder: The folder to delete.
    /// - Returns: The server's response.
    /// - Throws: An error if the folder cannot be deleted.
    ///
    /// - Warning: This operation is irreversible and will delete all messages in the folder.
    public func deleteFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.delete()
    }

    /// Renames a folder.
    ///
    /// - Parameters:
    ///   - path: The current path of the folder.
    ///   - newName: The new name for the folder.
    /// - Returns: The renamed `ImapFolder`.
    /// - Throws: An error if the folder cannot be renamed.
    public func renameFolder(_ path: String, to newName: String) throws -> ImapFolder {
        if let selectedFolder, selectedFolder.mailbox.name == path {
            return try selectedFolder.rename(to: newName)
        }
        let folder = try getFolder(path)
        return try folder.rename(to: newName)
    }

    /// Renames the specified folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to rename.
    ///   - newName: The new name for the folder.
    /// - Returns: The renamed `ImapFolder`.
    /// - Throws: An error if the folder cannot be renamed.
    public func renameFolder(_ folder: ImapFolder, to newName: String) throws -> ImapFolder {
        try folder.rename(to: newName)
    }

    /// Subscribes to a folder.
    ///
    /// Subscribed folders appear in LSUB responses and are typically shown
    /// in the user's folder list.
    ///
    /// - Parameter path: The full path of the folder to subscribe to.
    /// - Returns: The server's response.
    /// - Throws: An error if the subscription fails.
    public func subscribeFolder(_ path: String) throws -> ImapResponse {
        let folder = try getFolder(path)
        return try folder.subscribe()
    }

    /// Subscribes to the specified folder.
    ///
    /// - Parameter folder: The folder to subscribe to.
    /// - Returns: The server's response.
    /// - Throws: An error if the subscription fails.
    public func subscribeFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.subscribe()
    }

    /// Unsubscribes from a folder.
    ///
    /// - Parameter path: The full path of the folder to unsubscribe from.
    /// - Returns: The server's response.
    /// - Throws: An error if the unsubscription fails.
    public func unsubscribeFolder(_ path: String) throws -> ImapResponse {
        let folder = try getFolder(path)
        return try folder.unsubscribe()
    }

    /// Unsubscribes from the specified folder.
    ///
    /// - Parameter folder: The folder to unsubscribe from.
    /// - Returns: The server's response.
    /// - Throws: An error if the unsubscription fails.
    public func unsubscribeFolder(_ folder: ImapFolder) throws -> ImapResponse {
        try folder.unsubscribe()
    }

    /// Searches for messages matching the specified criteria string.
    ///
    /// This method requires a folder to be selected first. The criteria is passed
    /// directly to the server as an IMAP SEARCH command.
    ///
    /// - Parameter criteria: The IMAP search criteria string (e.g., "FROM smith SINCE 1-Feb-2024").
    /// - Returns: The search response containing matching message sequence numbers.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try store.openInbox(access: .readOnly)
    /// let results = try store.search("UNSEEN FROM \"john@example.com\"")
    /// ```
    public func search(_ criteria: String) throws -> ImapSearchResponse {
        try requireSelectedFolder().search(criteria)
    }

    /// Searches for messages matching the specified query.
    ///
    /// This method requires a folder to be selected first. The `SearchQuery` provides
    /// a type-safe way to build search criteria.
    ///
    /// - Parameter query: The search query to execute.
    /// - Returns: The search response containing matching message sequence numbers.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try store.openInbox(access: .readOnly)
    /// let results = try store.search(.and([.unseen, .from("john@example.com")]))
    /// ```
    public func search(_ query: SearchQuery) throws -> ImapSearchResponse {
        try requireSelectedFolder().search(query)
    }

    /// Searches for messages and returns unique identifiers (UIDs).
    ///
    /// - Parameter criteria: The IMAP search criteria string.
    /// - Returns: The search response containing matching message UIDs.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSearch(_ criteria: String) throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSearch(criteria)
    }

    /// Searches for messages and returns unique identifiers (UIDs).
    ///
    /// - Parameter query: The search query to execute.
    /// - Returns: The search response containing matching message UIDs.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSearch(_ query: SearchQuery) throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSearch(query)
    }

    /// Searches and sorts messages by the specified criteria.
    ///
    /// This method requires the SORT extension to be supported by the server.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria (e.g., `[.date(.ascending)]`).
    ///   - query: The search query to execute.
    ///   - charset: The character set for the search (default: "UTF-8").
    /// - Returns: The search response with results in sorted order.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func sort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try requireSelectedFolder().sort(orderBy, query: query, charset: charset)
    }

    /// Searches and sorts messages, returning unique identifiers (UIDs).
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set for the search (default: "UTF-8").
    /// - Returns: The search response with UIDs in sorted order.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try requireSelectedFolder().uidSort(orderBy, query: query, charset: charset)
    }

    /// Copies messages to another mailbox.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to copy (e.g., "1:*", "1,3,5").
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result with UIDVALIDITY and COPYUID information if available.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func copy(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().copy(set, to: mailbox)
    }

    /// Copies messages to another mailbox using a sequence set.
    ///
    /// - Parameters:
    ///   - set: The sequence set of messages to copy.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func copy(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().copy(set, to: mailbox)
    }

    /// Copies messages to another mailbox using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to copy.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidCopy(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().uidCopy(set, to: mailbox)
    }

    /// Moves messages to another mailbox.
    ///
    /// This method requires the MOVE extension. On servers without MOVE support,
    /// use `copy` followed by `store` to mark messages as deleted.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func move(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().move(set, to: mailbox)
    }

    /// Moves messages to another mailbox using a sequence set.
    ///
    /// - Parameters:
    ///   - set: The sequence set of messages to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func move(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().move(set, to: mailbox)
    }

    /// Moves messages to another mailbox using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidMove(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try requireSelectedFolder().uidMove(set, to: mailbox)
    }

    /// Identifies the client to the server and retrieves server identification.
    ///
    /// This method uses the IMAP ID extension (RFC 2971) to exchange client/server
    /// identification information.
    ///
    /// - Parameter parameters: Optional client identification parameters (e.g., "name", "version").
    /// - Returns: The server's identification response, or `nil` if not supported.
    /// - Throws: An error if the ID command fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let serverInfo = try store.id(["name": "MyApp", "version": "1.0"])
    /// print("Server: \(serverInfo?.name ?? "Unknown")")
    /// ```
    public func id(_ parameters: [String: String?]? = nil) throws -> ImapIdResponse? {
        try session.id(parameters)
    }

    /// Retrieves the server's namespace information.
    ///
    /// This method uses the NAMESPACE extension (RFC 2342) to discover the
    /// personal, other users', and shared namespace prefixes.
    ///
    /// - Returns: The namespace response, or `nil` if not supported.
    /// - Throws: An error if the NAMESPACE command fails.
    public func namespace() throws -> ImapNamespaceResponse? {
        try session.namespace()
    }

    /// Gets the quota for a quota root.
    ///
    /// This method uses the QUOTA extension (RFC 2087) to retrieve storage limits.
    ///
    /// - Parameter root: The quota root name.
    /// - Returns: The quota response, or `nil` if not supported.
    /// - Throws: An error if the GETQUOTA command fails.
    public func getQuota(_ root: String) throws -> ImapQuotaResponse? {
        try session.getQuota(root)
    }

    /// Gets the quota roots and quotas for a mailbox.
    ///
    /// - Parameter mailbox: The mailbox name.
    /// - Returns: The quota root result containing roots and their quotas.
    /// - Throws: An error if the GETQUOTAROOT command fails.
    public func getQuotaRoot(_ mailbox: String) throws -> ImapQuotaRootResult {
        try session.getQuotaRoot(mailbox)
    }

    /// Gets the access control list for a mailbox.
    ///
    /// This method uses the ACL extension (RFC 4314).
    ///
    /// - Parameter mailbox: The mailbox name.
    /// - Returns: The ACL response, or `nil` if not supported.
    /// - Throws: An error if the GETACL command fails.
    public func getAcl(_ mailbox: String) throws -> ImapAclResponse? {
        try session.getAcl(mailbox: mailbox)
    }

    /// Sets the access control list for a mailbox.
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name.
    ///   - identifier: The identifier (usually a username) to set rights for.
    ///   - rights: The rights string (e.g., "lrs" for lookup, read, seen).
    /// - Returns: The server's response.
    /// - Throws: An error if the SETACL command fails.
    public func setAcl(_ mailbox: String, identifier: String, rights: String) throws -> ImapResponse {
        try session.setAcl(mailbox: mailbox, identifier: identifier, rights: rights)
    }

    /// Lists the rights that can be granted to an identifier.
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name.
    ///   - identifier: The identifier to query rights for.
    /// - Returns: The list rights response, or `nil` if not supported.
    /// - Throws: An error if the LISTRIGHTS command fails.
    public func listRights(_ mailbox: String, identifier: String) throws -> ImapListRightsResponse? {
        try session.listRights(mailbox: mailbox, identifier: identifier)
    }

    /// Gets the current user's rights on a mailbox.
    ///
    /// - Parameter mailbox: The mailbox name.
    /// - Returns: The rights response, or `nil` if not supported.
    /// - Throws: An error if the MYRIGHTS command fails.
    public func myRights(_ mailbox: String) throws -> ImapMyRightsResponse? {
        try session.myRights(mailbox: mailbox)
    }

    /// Gets metadata entries for a mailbox.
    ///
    /// This method uses the METADATA extension (RFC 5464).
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name (use "" for server metadata).
    ///   - options: Optional metadata retrieval options.
    ///   - entries: The metadata entry names to retrieve.
    /// - Returns: The metadata response, or `nil` if not supported.
    /// - Throws: An error if the GETMETADATA command fails.
    public func getMetadata(
        _ mailbox: String,
        options: ImapMetadataOptions? = nil,
        entries: [String]
    ) throws -> ImapMetadataResponse? {
        try session.getMetadata(mailbox: mailbox, options: options, entries: entries)
    }

    /// Sets metadata entries for a mailbox.
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name (use "" for server metadata).
    ///   - entries: The metadata entries to set.
    /// - Returns: The server's response.
    /// - Throws: An error if the SETMETADATA command fails.
    public func setMetadata(_ mailbox: String, entries: [ImapMetadataEntry]) throws -> ImapResponse {
        try session.setMetadata(mailbox: mailbox, entries: entries)
    }

    /// Gets annotations for a mailbox.
    ///
    /// This method uses the ANNOTATE extension.
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name.
    ///   - entries: The annotation entry names.
    ///   - attributes: The attributes to retrieve.
    /// - Returns: The annotation result, or `nil` if not supported.
    /// - Throws: An error if the GETANNOTATION command fails.
    public func getAnnotation(
        _ mailbox: String,
        entries: [String],
        attributes: [String]
    ) throws -> ImapAnnotationResult? {
        try session.getAnnotation(mailbox: mailbox, entries: entries, attributes: attributes)
    }

    /// Sets an annotation for a mailbox.
    ///
    /// - Parameters:
    ///   - mailbox: The mailbox name.
    ///   - entry: The annotation entry name.
    ///   - attributes: The attributes to set.
    /// - Returns: The server's response.
    /// - Throws: An error if the SETANNOTATION command fails.
    public func setAnnotation(
        _ mailbox: String,
        entry: String,
        attributes: [ImapAnnotationAttribute]
    ) throws -> ImapResponse {
        try session.setAnnotation(mailbox: mailbox, entry: entry, attributes: attributes)
    }

    /// Fetches message summaries for the specified message set.
    ///
    /// Message summaries include envelope information, flags, size, and other
    /// metadata without downloading the full message body.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to fetch (e.g., "1:10", "1,3,5").
    ///   - request: The fetch request specifying which data items to retrieve.
    ///   - previewLength: Maximum length of the preview text (default: 512).
    /// - Returns: An array of message summaries.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try store.openInbox(access: .readOnly)
    /// let summaries = try store.fetchSummaries("1:10", request: FetchRequest.envelope)
    /// for summary in summaries {
    ///     print("Subject: \(summary.envelope?.subject ?? "")")
    /// }
    /// ```
    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try requireSelectedFolder().fetchSummaries(set, request: request, previewLength: previewLength)
    }

    /// Fetches message summaries using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to fetch.
    ///   - request: The fetch request specifying which data items to retrieve.
    ///   - previewLength: Maximum length of the preview text (default: 512).
    /// - Returns: An array of message summaries.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidFetchSummaries(
        _ set: UniqueIdSet,
        request: FetchRequest,
        previewLength: Int = 512
    ) throws -> [MessageSummary] {
        try requireSelectedFolder().uidFetchSummaries(set, request: request, previewLength: previewLength)
    }

    /// Searches and returns results as an ID set with validity.
    ///
    /// - Parameters:
    ///   - criteria: The IMAP search criteria string.
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func searchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().searchIdSet(criteria, validity: validity)
    }

    /// Searches using a query and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - query: The search query to execute.
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func searchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().searchIdSet(query, validity: validity)
    }

    /// Searches using UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - criteria: The IMAP search criteria string.
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the UID results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSearchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSearchIdSet(criteria, validity: validity)
    }

    /// Searches using a query with UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - query: The search query to execute.
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the UID results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSearchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSearchIdSet(query, validity: validity)
    }

    /// Sorts messages and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set for the search (default: "UTF-8").
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the sorted results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try requireSelectedFolder().sortIdSet(orderBy, query: query, charset: charset, validity: validity)
    }

    /// Sorts messages using UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set for the search (default: "UTF-8").
    ///   - validity: The UIDVALIDITY value to associate with the results.
    /// - Returns: An `ImapSearchIdSet` containing the sorted UID results.
    /// - Throws: `ImapMailStoreError.noSelectedFolder` if no folder is selected.
    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try requireSelectedFolder().uidSortIdSet(orderBy, query: query, charset: charset, validity: validity)
    }

    /// Updates the currently selected folder reference.
    ///
    /// This method is called internally when folders are opened or closed.
    internal func updateSelectedFolder(_ folder: ImapFolder?, access: FolderAccess?) {
        selectedFolder = folder
        selectedAccess = access
    }
}

/// Represents an IMAP folder (mailbox) on the server.
///
/// An `ImapFolder` provides methods for accessing and manipulating messages within
/// a mailbox. Before performing message operations, the folder must be opened using
/// `open(_:)` or one of its convenience variants.
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
/// let folder = try store.getFolder("Archive/2024")
/// try folder.open(.readOnly)
///
/// // Search for messages
/// let results = try folder.search(.unseen)
///
/// // Close the folder
/// try folder.close()
/// ```
///
/// ## See Also
///
/// - ``ImapMailStore``
/// - ``ImapMailbox``
/// - ``AsyncImapFolder``
public final class ImapFolder: MailFolderBase {
    /// The underlying mailbox information including name and attributes.
    public let mailbox: ImapMailbox

    private let session: ImapSession
    private weak var store: ImapMailStore?

    /// Initializes a new IMAP folder with the given session and mailbox.
    ///
    /// - Parameters:
    ///   - session: The IMAP session to use for commands.
    ///   - mailbox: The mailbox information.
    ///   - store: The parent mail store (held weakly to avoid retain cycles).
    public init(session: ImapSession, mailbox: ImapMailbox, store: ImapMailStore?) {
        self.session = session
        self.mailbox = mailbox
        self.store = store
        super.init(fullName: mailbox.decodedName, delimiter: mailbox.delimiter)
    }

    /// The raw (encoded) mailbox name as it appears on the server.
    ///
    /// This may contain modified UTF-7 encoding for international characters.
    public var rawName: String {
        mailbox.name
    }

    /// Opens the folder with the specified access mode.
    ///
    /// This method issues a SELECT (for read-write) or EXAMINE (for read-only) command.
    /// The folder must be opened before performing message operations.
    ///
    /// - Parameter access: The desired access mode.
    /// - Returns: The server's response containing mailbox status.
    /// - Throws: An error if the folder cannot be opened.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let folder = try store.getFolder("INBOX")
    /// try folder.open(.readWrite)
    /// // Folder is now ready for message operations
    /// ```
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

    /// Opens the folder in read-only mode.
    ///
    /// This is a convenience method equivalent to `open(.readOnly)`.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the folder cannot be opened.
    public func openReadOnly() throws -> ImapResponse {
        try open(.readOnly)
    }

    /// Opens the folder in read-write mode.
    ///
    /// This is a convenience method equivalent to `open(.readWrite)`.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the folder cannot be opened.
    public func openReadWrite() throws -> ImapResponse {
        try open(.readWrite)
    }

    /// Closes the folder.
    ///
    /// If the folder was opened in read-write mode, this command also expunges
    /// any messages marked for deletion.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the CLOSE command fails.
    public func close() throws -> ImapResponse {
        let response = try session.close()
        updateOpenState(nil)
        store?.updateSelectedFolder(nil, access: nil)
        return response
    }

    /// Permanently removes messages marked for deletion.
    ///
    /// This command removes all messages with the \Deleted flag from the mailbox.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the EXPUNGE command fails.
    public func expunge() throws -> ImapResponse {
        try session.expunge()
    }

    /// Creates this folder on the server.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the CREATE command fails.
    public func create() throws -> ImapResponse {
        try session.create(mailbox: mailbox.name)
    }

    /// Deletes this folder from the server.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the DELETE command fails.
    ///
    /// - Warning: This operation is irreversible and deletes all messages.
    public func delete() throws -> ImapResponse {
        let response = try session.delete(mailbox: mailbox.name)
        if store?.selectedFolder === self {
            updateOpenState(nil)
            store?.updateSelectedFolder(nil, access: nil)
        }
        return response
    }

    /// Renames this folder.
    ///
    /// - Parameter newName: The new name for the folder.
    /// - Returns: A new `ImapFolder` with the updated name.
    /// - Throws: An error if the RENAME command fails.
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

    /// Subscribes to this folder.
    ///
    /// Subscribed folders appear in LSUB responses.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the SUBSCRIBE command fails.
    public func subscribe() throws -> ImapResponse {
        try session.subscribe(mailbox: mailbox.name)
    }

    /// Unsubscribes from this folder.
    ///
    /// - Returns: The server's response.
    /// - Throws: An error if the UNSUBSCRIBE command fails.
    public func unsubscribe() throws -> ImapResponse {
        try session.unsubscribe(mailbox: mailbox.name)
    }

    /// Gets the status of this folder.
    ///
    /// This method can be used to retrieve information about a folder without
    /// selecting it. Common status items include MESSAGES, RECENT, UNSEEN,
    /// UIDNEXT, and UIDVALIDITY.
    ///
    /// - Parameter items: The status items to retrieve.
    /// - Returns: The status response.
    /// - Throws: An error if the STATUS command fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let status = try folder.status(items: ["MESSAGES", "UNSEEN"])
    /// print("Total: \(status.messages ?? 0), Unseen: \(status.unseen ?? 0)")
    /// ```
    public func status(items: [String]) throws -> ImapStatusResponse {
        try session.status(mailbox: mailbox.name, items: items)
    }

    /// Searches for messages matching the specified criteria.
    ///
    /// - Parameter criteria: The IMAP search criteria string.
    /// - Returns: The search response containing matching sequence numbers.
    /// - Throws: An error if the SEARCH command fails.
    public func search(_ criteria: String) throws -> ImapSearchResponse {
        try session.search(criteria)
    }

    /// Searches for messages matching the specified query.
    ///
    /// - Parameter query: The search query to execute.
    /// - Returns: The search response containing matching sequence numbers.
    /// - Throws: An error if the SEARCH command fails.
    public func search(_ query: SearchQuery) throws -> ImapSearchResponse {
        try session.search(query)
    }

    /// Searches and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - criteria: The IMAP search criteria string.
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the results.
    /// - Throws: An error if the SEARCH command fails.
    public func searchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try search(criteria).idSet(validity: validity)
    }

    /// Searches using a query and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - query: The search query to execute.
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the results.
    /// - Throws: An error if the SEARCH command fails.
    public func searchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try search(query).idSet(validity: validity)
    }

    /// Searches for messages and returns unique identifiers.
    ///
    /// - Parameter criteria: The IMAP search criteria string.
    /// - Returns: The search response containing matching UIDs.
    /// - Throws: An error if the UID SEARCH command fails.
    public func uidSearch(_ criteria: String) throws -> ImapSearchResponse {
        try session.uidSearch(criteria)
    }

    /// Searches for messages using a query and returns unique identifiers.
    ///
    /// - Parameter query: The search query to execute.
    /// - Returns: The search response containing matching UIDs.
    /// - Throws: An error if the UID SEARCH command fails.
    public func uidSearch(_ query: SearchQuery) throws -> ImapSearchResponse {
        try session.uidSearch(query)
    }

    /// Searches using UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - criteria: The IMAP search criteria string.
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the UID results.
    /// - Throws: An error if the UID SEARCH command fails.
    public func uidSearchIdSet(_ criteria: String, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try uidSearch(criteria).idSet(validity: validity)
    }

    /// Searches using a query with UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - query: The search query to execute.
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the UID results.
    /// - Throws: An error if the UID SEARCH command fails.
    public func uidSearchIdSet(_ query: SearchQuery, validity: UInt32 = 0) throws -> ImapSearchIdSet {
        try uidSearch(query).idSet(validity: validity)
    }

    /// Searches and sorts messages by the specified criteria.
    ///
    /// Requires the SORT extension to be supported by the server.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set (default: "UTF-8").
    /// - Returns: The search response with sorted results.
    /// - Throws: An error if the SORT command fails.
    public func sort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try session.sort(orderBy, query: query, charset: charset)
    }

    /// Searches and sorts messages, returning unique identifiers.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set (default: "UTF-8").
    /// - Returns: The search response with sorted UIDs.
    /// - Throws: An error if the UID SORT command fails.
    public func uidSort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try session.uidSort(orderBy, query: query, charset: charset)
    }

    /// Copies messages to another mailbox.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to copy.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result with COPYUID information if available.
    /// - Throws: An error if the COPY command fails.
    public func copy(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try session.copy(set, to: mailbox)
    }

    /// Copies messages to another mailbox using a sequence set.
    ///
    /// - Parameters:
    ///   - set: The sequence set of messages to copy.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result.
    /// - Throws: An error if the COPY command fails.
    public func copy(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try session.copy(set, to: mailbox)
    }

    /// Copies messages to another mailbox using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to copy.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The copy result.
    /// - Throws: An error if the UID COPY command fails.
    public func uidCopy(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try session.uidCopy(set, to: mailbox)
    }

    /// Moves messages to another mailbox.
    ///
    /// Requires the MOVE extension.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: An error if the MOVE command fails.
    public func move(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try session.move(set, to: mailbox)
    }

    /// Moves messages to another mailbox using a sequence set.
    ///
    /// - Parameters:
    ///   - set: The sequence set of messages to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: An error if the MOVE command fails.
    public func move(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try session.move(set, to: mailbox)
    }

    /// Moves messages to another mailbox using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to move.
    ///   - mailbox: The destination mailbox name.
    /// - Returns: The move result.
    /// - Throws: An error if the UID MOVE command fails.
    public func uidMove(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try session.uidMove(set, to: mailbox)
    }

    /// Sorts messages and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set (default: "UTF-8").
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the sorted results.
    /// - Throws: An error if the SORT command fails.
    public func sortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try sort(orderBy, query: query, charset: charset).idSet(validity: validity)
    }

    /// Sorts messages using UIDs and returns results as an ID set.
    ///
    /// - Parameters:
    ///   - orderBy: The sort criteria.
    ///   - query: The search query to execute.
    ///   - charset: The character set (default: "UTF-8").
    ///   - validity: The UIDVALIDITY to associate with results.
    /// - Returns: An `ImapSearchIdSet` containing the sorted UID results.
    /// - Throws: An error if the UID SORT command fails.
    public func uidSortIdSet(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        validity: UInt32 = 0
    ) throws -> ImapSearchIdSet {
        try uidSort(orderBy, query: query, charset: charset).idSet(validity: validity)
    }

    /// Fetches message summaries for the specified message set.
    ///
    /// - Parameters:
    ///   - set: The message sequence numbers to fetch.
    ///   - request: The fetch request specifying data items.
    ///   - previewLength: Maximum preview text length (default: 512).
    /// - Returns: An array of message summaries.
    /// - Throws: An error if the FETCH command fails.
    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    /// Fetches message summaries using unique identifiers.
    ///
    /// - Parameters:
    ///   - set: The UID set of messages to fetch.
    ///   - request: The fetch request specifying data items.
    ///   - previewLength: Maximum preview text length (default: 512).
    /// - Returns: An array of message summaries.
    /// - Throws: An error if the UID FETCH command fails.
    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }

    /// Gets the quota roots and quotas for this folder.
    ///
    /// - Returns: The quota root result.
    /// - Throws: An error if the GETQUOTAROOT command fails.
    public func getQuotaRoot() throws -> ImapQuotaRootResult {
        try session.getQuotaRoot(mailbox.name)
    }

    /// Gets the access control list for this folder.
    ///
    /// - Returns: The ACL response, or `nil` if not supported.
    /// - Throws: An error if the GETACL command fails.
    public func getAcl() throws -> ImapAclResponse? {
        try session.getAcl(mailbox: mailbox.name)
    }

    /// Sets the access control list for this folder.
    ///
    /// - Parameters:
    ///   - identifier: The identifier to set rights for.
    ///   - rights: The rights string.
    /// - Returns: The server's response.
    /// - Throws: An error if the SETACL command fails.
    public func setAcl(identifier: String, rights: String) throws -> ImapResponse {
        try session.setAcl(mailbox: mailbox.name, identifier: identifier, rights: rights)
    }

    /// Lists the rights that can be granted to an identifier.
    ///
    /// - Parameter identifier: The identifier to query.
    /// - Returns: The list rights response, or `nil` if not supported.
    /// - Throws: An error if the LISTRIGHTS command fails.
    public func listRights(identifier: String) throws -> ImapListRightsResponse? {
        try session.listRights(mailbox: mailbox.name, identifier: identifier)
    }

    /// Gets the current user's rights on this folder.
    ///
    /// - Returns: The rights response, or `nil` if not supported.
    /// - Throws: An error if the MYRIGHTS command fails.
    public func myRights() throws -> ImapMyRightsResponse? {
        try session.myRights(mailbox: mailbox.name)
    }

    /// Gets metadata entries for this folder.
    ///
    /// - Parameters:
    ///   - options: Optional retrieval options.
    ///   - entries: The metadata entry names.
    /// - Returns: The metadata response, or `nil` if not supported.
    /// - Throws: An error if the GETMETADATA command fails.
    public func getMetadata(options: ImapMetadataOptions? = nil, entries: [String]) throws -> ImapMetadataResponse? {
        try session.getMetadata(mailbox: mailbox.name, options: options, entries: entries)
    }

    /// Sets metadata entries for this folder.
    ///
    /// - Parameter entries: The metadata entries to set.
    /// - Returns: The server's response.
    /// - Throws: An error if the SETMETADATA command fails.
    public func setMetadata(entries: [ImapMetadataEntry]) throws -> ImapResponse {
        try session.setMetadata(mailbox: mailbox.name, entries: entries)
    }

    /// Gets annotations for this folder.
    ///
    /// - Parameters:
    ///   - entries: The annotation entry names.
    ///   - attributes: The attributes to retrieve.
    /// - Returns: The annotation result, or `nil` if not supported.
    /// - Throws: An error if the GETANNOTATION command fails.
    public func getAnnotation(entries: [String], attributes: [String]) throws -> ImapAnnotationResult? {
        try session.getAnnotation(mailbox: mailbox.name, entries: entries, attributes: attributes)
    }

    /// Sets an annotation for this folder.
    ///
    /// - Parameters:
    ///   - entry: The annotation entry name.
    ///   - attributes: The attributes to set.
    /// - Returns: The server's response.
    /// - Throws: An error if the SETANNOTATION command fails.
    public func setAnnotation(entry: String, attributes: [ImapAnnotationAttribute]) throws -> ImapResponse {
        try session.setAnnotation(mailbox: mailbox.name, entry: entry, attributes: attributes)
    }
}
