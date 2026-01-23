//
// ImapMailStore.swift
//
// IMAP mail store and folder wrappers.
//

public final class ImapMailStore: MailServiceBase<ImapResponse>, MailStore {
    public typealias FolderType = ImapFolder

    private let session: ImapSession

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
        super.disconnect()
    }

    public func getFolder(_ path: String) throws -> ImapFolder {
        let mailbox = ImapMailbox(kind: .list, name: path, delimiter: nil, attributes: [])
        return ImapFolder(session: session, mailbox: mailbox)
    }

    public func getFolders(reference: String, pattern: String, subscribedOnly: Bool = false) throws -> [ImapFolder] {
        let mailboxes = subscribedOnly
            ? try session.lsub(reference: reference, mailbox: pattern)
            : try session.list(reference: reference, mailbox: pattern)
        return mailboxes.map { ImapFolder(session: session, mailbox: $0) }
    }
}

public final class ImapFolder: MailFolder {
    public let mailbox: ImapMailbox
    public let fullName: String
    public let name: String

    private let session: ImapSession

    public init(session: ImapSession, mailbox: ImapMailbox) {
        self.session = session
        self.mailbox = mailbox
        self.fullName = mailbox.decodedName
        if let delimiter = mailbox.delimiter, let last = mailbox.decodedName.split(separator: Character(delimiter)).last {
            self.name = String(last)
        } else {
            self.name = mailbox.decodedName
        }
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.fetchSummaries(set, request: request, previewLength: previewLength)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        try session.uidFetchSummaries(set, request: request, previewLength: previewLength)
    }
}
