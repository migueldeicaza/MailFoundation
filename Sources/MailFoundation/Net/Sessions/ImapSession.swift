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
// ImapSession.swift
//
// Higher-level synchronous IMAP session helpers.
//

public final class ImapSession {
    private let client: ImapClient
    private let transport: Transport
    private let maxReads: Int
    private var idleTag: String?
    public private(set) var selectedMailbox: String?
    public private(set) var selectedState = ImapSelectedState()
    public private(set) var namespaces: ImapNamespaceResponse?
    public private(set) var specialUseMailboxes: [ImapMailbox] = []

    public var capabilities: ImapCapabilities? {
        client.capabilities
    }

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.transport = transport
        self.client = ImapClient(protocolLogger: protocolLogger)
        self.maxReads = maxReads
    }

    @discardableResult
    public func connect() throws -> ImapResponse {
        client.connect(transport: transport)
        guard let greeting = waitForGreeting() else {
            throw SessionError.timeout
        }
        if greeting.status == .ok || greeting.status == .preauth {
            return greeting
        }
        throw SessionError.imapError(status: greeting.status, text: greeting.text)
    }

    public func disconnect() {
        _ = client.send(.logout)
        transport.close()
        selectedMailbox = nil
        selectedState = ImapSelectedState()
        namespaces = nil
        specialUseMailboxes = []
        idleTag = nil
    }

    public func capability() throws -> ImapResponse {
        let command = client.send(.capability)
        try ensureWrite()
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func login(user: String, password: String) throws -> ImapResponse {
        let initialCapabilitiesVersion = client.capabilitiesVersion
        let command = client.send(.login(user, password))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        if client.capabilitiesVersion == initialCapabilitiesVersion {
            _ = try? capability()
        }
        try postAuthenticate()
        return response
    }

    /// Authenticates using SASL mechanism.
    ///
    /// - Parameter auth: The SASL authentication configuration.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails.
    public func authenticate(_ auth: ImapAuthentication) throws -> ImapResponse {
        let initialCapabilitiesVersion = client.capabilitiesVersion
        let supportsSaslIr = client.capabilities?.supports("SASL-IR") ?? false
        var pendingInitialResponse = supportsSaslIr ? nil : auth.initialResponse
        let command = client.send(.authenticate(auth.mechanism, initialResponse: supportsSaslIr ? auth.initialResponse : nil))
        try ensureWrite()

        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response {
                    if case .continuation = response.kind {
                        let challenge = response.text
                        let responseData: String
                        if let initial = pendingInitialResponse {
                            responseData = initial
                            pendingInitialResponse = nil
                        } else if let responder = auth.responder {
                            responseData = try responder(challenge)
                        } else {
                            responseData = ""
                        }

                        if responseData.isEmpty {
                            client.sendLiteral(Array("\r\n".utf8))
                        } else {
                            client.sendLiteral(Array("\(responseData)\r\n".utf8))
                        }
                        try ensureWrite()
                        continue
                    }
                    if case let .tagged(tag) = response.kind, tag == command.tag {
                        guard response.isOk else {
                            throw SessionError.imapError(status: response.status, text: response.text)
                        }
                        if client.capabilitiesVersion == initialCapabilitiesVersion {
                            _ = try? capability()
                        }
                        try postAuthenticate()
                        return response
                    }
                }
            }
        }

        throw SessionError.timeout
    }

    /// Authenticates using XOAUTH2 with an OAuth access token.
    public func authenticateXoauth2(user: String, accessToken: String) throws -> ImapResponse {
        let auth = ImapSasl.xoauth2(username: user, accessToken: accessToken)
        return try authenticate(auth)
    }

    /// Authenticates using SASL with automatic mechanism selection.
    ///
    /// - Parameters:
    ///   - user: The username.
    ///   - password: The password.
    ///   - mechanisms: Optional list of allowed mechanisms.
    ///   - host: Optional server hostname for DIGEST-MD5 and GSSAPI.
    ///   - channelBinding: Optional SCRAM channel binding data. If `nil`, the session uses
    ///     the transport's TLS channel binding when available.
    /// - Returns: The server's response.
    /// - Throws: An error if authentication fails or no mechanism is supported.
    public func authenticateSasl(
        user: String,
        password: String,
        mechanisms: [String]? = nil,
        host: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) throws -> ImapResponse {
        let availableMechanisms: [String]
        if let mechanisms {
            availableMechanisms = mechanisms
        } else {
            if client.capabilities == nil {
                _ = try? capability()
            }
            availableMechanisms = client.capabilities?.saslMechanisms() ?? []
        }

        let resolvedChannelBinding = channelBinding ?? (transport as? StartTlsTransport)?.scramChannelBinding
        guard let authentication = ImapSasl.chooseAuthentication(
            username: user,
            password: password,
            mechanisms: availableMechanisms,
            host: host,
            channelBinding: resolvedChannelBinding
        ) else {
            throw SessionError.imapError(status: .no, text: "No supported SASL mechanisms.")
        }
        return try authenticate(authentication)
    }

    public func noop() throws -> ImapResponse {
        let command = client.send(.noop)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func enable(_ capabilities: [String]) throws -> [String] {
        try ensureAuthenticated()
        let command = client.send(.enable(capabilities))
        try ensureWrite()
        var enabled: [String] = []
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = ImapEnabledResponse.parse(message.line) {
                    enabled.append(contentsOf: response.capabilities)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return enabled
                }
            }
        }
        throw SessionError.timeout
    }

    public func select(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.select(mailbox))
        try ensureWrite()
        var reads = 0
        var nextState = ImapSelectedState()

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                applySelectedState(&nextState, mailbox: mailbox, from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    selectedMailbox = mailbox
                    selectedState = nextState
                    return response
                }
            }
        }

        throw SessionError.timeout
    }

    public func examine(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.examine(mailbox))
        try ensureWrite()
        var reads = 0
        var nextState = ImapSelectedState()

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                applySelectedState(&nextState, mailbox: mailbox, from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    selectedMailbox = mailbox
                    selectedState = nextState
                    return response
                }
            }
        }

        throw SessionError.timeout
    }

    public func close() throws -> ImapResponse {
        try ensureSelected()
        let command = client.send(.close)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        selectedMailbox = nil
        selectedState = ImapSelectedState()
        return response
    }

    public func check() throws -> ImapResponse {
        try ensureSelected()
        let command = client.send(.check)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func expunge() throws -> ImapResponse {
        try ensureSelected()
        let command = client.send(.expunge)
        try ensureWrite()
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func create(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.create(mailbox))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func delete(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.delete(mailbox))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func rename(mailbox: String, newName: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.rename(mailbox, newName))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func subscribe(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.subscribe(mailbox))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func unsubscribe(mailbox: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.unsubscribe(mailbox))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func namespace() throws -> ImapNamespaceResponse? {
        try ensureAuthenticated()
        let command = client.send(.namespace)
        try ensureWrite()
        var result: ImapNamespaceResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let parsed = ImapNamespaceResponse.parse(message.line) {
                    result = parsed
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func getQuota(_ root: String) throws -> ImapQuotaResponse? {
        try ensureAuthenticated()
        let command = client.send(.getQuota(root))
        try ensureWrite()
        var result: ImapQuotaResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let quota = ImapQuotaResponse.parse(message.line) {
                    result = quota
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func getQuotaRoot(_ mailbox: String) throws -> ImapQuotaRootResult {
        try ensureAuthenticated()
        let command = client.send(.getQuotaRoot(mailbox))
        try ensureWrite()
        var root: ImapQuotaRootResponse?
        var quotas: [ImapQuotaResponse] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let parsedRoot = ImapQuotaRootResponse.parse(message.line) {
                    root = parsedRoot
                }
                if let quota = ImapQuotaResponse.parse(message.line) {
                    quotas.append(quota)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapQuotaRootResult(quotaRoot: root, quotas: quotas)
                }
            }
        }
        throw SessionError.timeout
    }

    public func getAcl(mailbox: String) throws -> ImapAclResponse? {
        try ensureAuthenticated()
        let command = client.send(.getAcl(mailbox))
        try ensureWrite()
        var result: ImapAclResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let acl = ImapAclResponse.parse(message.line) {
                    result = acl
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func setAcl(mailbox: String, identifier: String, rights: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.setAcl(mailbox, identifier: identifier, rights: rights))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func listRights(mailbox: String, identifier: String) throws -> ImapListRightsResponse? {
        try ensureAuthenticated()
        let command = client.send(.listRights(mailbox, identifier: identifier))
        try ensureWrite()
        var result: ImapListRightsResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let rights = ImapListRightsResponse.parse(message.line) {
                    result = rights
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func myRights(mailbox: String) throws -> ImapMyRightsResponse? {
        try ensureAuthenticated()
        let command = client.send(.myRights(mailbox))
        try ensureWrite()
        var result: ImapMyRightsResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let rights = ImapMyRightsResponse.parse(message.line) {
                    result = rights
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func getMetadata(
        mailbox: String,
        options: ImapMetadataOptions? = nil,
        entries: [String]
    ) throws -> ImapMetadataResponse? {
        try ensureAuthenticated()
        let command = client.send(.getMetadata(mailbox, options: options, entries: entries))
        try ensureWrite()
        var result: ImapMetadataResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let metadata = ImapMetadataResponse.parse(message) {
                    result = metadata
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }
        throw SessionError.timeout
    }

    public func setMetadata(mailbox: String, entries: [ImapMetadataEntry]) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.setMetadata(mailbox, entries: entries))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func getAnnotation(
        mailbox: String,
        entries: [String],
        attributes: [String]
    ) throws -> ImapAnnotationResult? {
        try ensureAuthenticated()
        let command = client.send(.getAnnotation(mailbox, entries: entries, attributes: attributes))
        try ensureWrite()
        var mailboxName: String?
        var entriesResult: [ImapAnnotationEntry] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let parsed = ImapAnnotationResponse.parse(message) {
                    mailboxName = parsed.mailbox
                    entriesResult.append(parsed.entry)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    guard let mailboxName else {
                        return nil
                    }
                    return ImapAnnotationResult(mailbox: mailboxName, entries: entriesResult)
                }
            }
        }
        throw SessionError.timeout
    }

    public func setAnnotation(
        mailbox: String,
        entry: String,
        attributes: [ImapAnnotationAttribute]
    ) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.setAnnotation(mailbox, entry: entry, attributes: attributes))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func list(reference: String, mailbox: String) throws -> [ImapMailbox] {
        let responses = try listResponses(reference: reference, mailbox: mailbox)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func listExtended(
        reference: String,
        mailbox: String,
        returns: [ImapListReturnOption] = []
    ) throws -> [ImapMailbox] {
        let responses = try listExtendedResponses(reference: reference, mailbox: mailbox, returns: returns)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func listResponses(reference: String, mailbox: String) throws -> [ImapMailboxListResponse] {
        try listResponses(command: .list(reference, mailbox))
    }

    public func listExtendedResponses(
        reference: String,
        mailbox: String,
        returns: [ImapListReturnOption] = []
    ) throws -> [ImapMailboxListResponse] {
        try listResponses(command: .listExtended(reference, mailbox, returns: returns))
    }

    private func listResponses(command: ImapCommandKind) throws -> [ImapMailboxListResponse] {
        try ensureAuthenticated()
        let command = client.send(command)
        try ensureWrite()
        var responses: [ImapMailboxListResponse] = []
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let list = ImapMailboxListResponse.parse(message) {
                    responses.append(list)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    private func listSpecialUse(reference: String, mailbox: String) throws -> [ImapMailbox] {
        let responses = try listResponses(command: .listSpecialUse(reference, mailbox))
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    private func xlist(reference: String, mailbox: String) throws -> [ImapMailbox] {
        let responses = try listResponses(command: .xlist(reference, mailbox))
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func lsub(reference: String, mailbox: String) throws -> [ImapMailbox] {
        let responses = try lsubResponses(reference: reference, mailbox: mailbox)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func lsubResponses(reference: String, mailbox: String) throws -> [ImapMailboxListResponse] {
        try ensureAuthenticated()
        let command = client.send(.lsub(reference, mailbox))
        try ensureWrite()
        var responses: [ImapMailboxListResponse] = []
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let list = ImapMailboxListResponse.parse(message) {
                    responses.append(list)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    public func listStatus(
        reference: String,
        mailbox: String,
        items: [String] = ["MESSAGES", "UNSEEN", "UIDNEXT", "UIDVALIDITY"]
    ) throws -> [ImapListStatusResponse] {
        try ensureAuthenticated()
        let normalizedItems = items.isEmpty ? ["MESSAGES"] : items
        let command = client.send(.listStatus(reference, mailbox, items: normalizedItems))
        try ensureWrite()
        var responses: [ImapListStatusResponse] = []
        var mailboxMap: [String: ImapMailbox] = [:]
        var statusMap: [String: [String: Int]] = [:]
        var seen: Set<String> = []
        var reads = 0

        func appendStatus(name: String, mailbox: ImapMailbox, items: [String: Int]) {
            guard !seen.contains(name) else { return }
            responses.append(ImapListStatusResponse(mailbox: mailbox, statusItems: items))
            seen.insert(name)
        }

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let list = ImapMailboxListResponse.parse(message) {
                    let mailbox = list.toMailbox()
                    mailboxMap[mailbox.name] = mailbox
                    if let items = statusMap[mailbox.name] {
                        appendStatus(name: mailbox.name, mailbox: mailbox, items: items)
                    }
                }
                if let listStatus = ImapListStatusResponse.parse(message) {
                    responses.append(listStatus)
                    seen.insert(listStatus.mailbox.name)
                }
                if let status = ImapStatusResponse.parse(message) {
                    statusMap[status.mailbox] = status.items
                    if let mailbox = mailboxMap[status.mailbox] {
                        appendStatus(name: status.mailbox, mailbox: mailbox, items: status.items)
                    }
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    for (name, items) in statusMap {
                        if let mailbox = mailboxMap[name] {
                            appendStatus(name: name, mailbox: mailbox, items: items)
                        }
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    public func search(_ criteria: String) throws -> ImapSearchResponse {
        try ensureSelected()
        let command = client.send(.search(criteria))
        try ensureWrite()
        var result = ImapSearchResponse(ids: [], isUid: false)
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let esearch = ImapESearchResponse.parse(message.line) {
                    result = ImapSearchResponse(esearch: esearch, defaultIsUid: false)
                } else if let search = ImapSearchResponse.parse(message.line) {
                    result = ImapSearchResponse(ids: search.ids, isUid: false)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }

        throw SessionError.timeout
    }

    public func search(_ query: SearchQuery) throws -> ImapSearchResponse {
        try search(query.optimized().serialize())
    }

    public func sort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try ensureSelected()
        try ImapSort.validateCapabilities(orderBy: orderBy, capabilities: client.capabilities)
        let kind = try ImapCommandKind.sort(query, orderBy: orderBy, charset: charset)
        let command = client.send(kind)
        try ensureWrite()
        var result = ImapSearchResponse(ids: [], isUid: false)
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let esearch = ImapESearchResponse.parse(message.line) {
                    result = ImapSearchResponse(esearch: esearch, defaultIsUid: false)
                } else if let search = ImapSearchResponse.parse(message.line) {
                    result = ImapSearchResponse(ids: search.ids, isUid: false)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidSearch(_ criteria: String) throws -> ImapSearchResponse {
        try ensureSelected()
        let command = client.send(.uidSearch(criteria))
        try ensureWrite()
        var result = ImapSearchResponse(ids: [], isUid: true)
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let esearch = ImapESearchResponse.parse(message.line) {
                    result = ImapSearchResponse(esearch: esearch, defaultIsUid: true)
                } else if let search = ImapSearchResponse.parse(message.line) {
                    result = ImapSearchResponse(ids: search.ids, isUid: true)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidSearch(_ query: SearchQuery) throws -> ImapSearchResponse {
        try uidSearch(query.optimized().serialize())
    }

    public func uidSort(_ orderBy: [OrderBy], query: SearchQuery, charset: String = "UTF-8") throws -> ImapSearchResponse {
        try ensureSelected()
        try ImapSort.validateCapabilities(orderBy: orderBy, capabilities: client.capabilities)
        let kind = try ImapCommandKind.uidSort(query, orderBy: orderBy, charset: charset)
        let command = client.send(kind)
        try ensureWrite()
        var result = ImapSearchResponse(ids: [], isUid: true)
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let esearch = ImapESearchResponse.parse(message.line) {
                    result = ImapSearchResponse(esearch: esearch, defaultIsUid: true)
                } else if let search = ImapSearchResponse.parse(message.line) {
                    result = ImapSearchResponse(ids: search.ids, isUid: true)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return result
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetch(_ set: String, items: String) throws -> [ImapFetchResponse] {
        let result = try fetchWithQresync(set, items: items)
        return result.responses
    }

    public func fetch(_ set: String, request: FetchRequest) throws -> [ImapFetchResponse] {
        try fetch(set, items: request.imapItemList)
    }

    public func id(_ parameters: [String: String?]? = nil) throws -> ImapIdResponse? {
        let command = client.send(.id(ImapId.buildArguments(parameters)))
        try ensureWrite()
        var reads = 0
        var response: ImapIdResponse?

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let idResponse = ImapIdResponse.parse(message.line) {
                    response = idResponse
                }
                if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                    guard tagged.isOk else {
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                    return response
                }
            }
        }

        throw SessionError.timeout
    }

    public func copy(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try ensureSelected()
        let command = client.send(.copy(set, mailbox))
        try ensureWrite()
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let copyUid = ImapResponseCode.copyUid(from: response.text)
                    return ImapCopyResult(response: response, copyUid: copyUid)
                }
            }
        }

        throw SessionError.timeout
    }

    public func copy(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try copy(set.description, to: mailbox)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try ensureSelected()
        let command = client.send(.uidCopy(set.description, mailbox))
        try ensureWrite()
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let copyUid = ImapResponseCode.copyUid(from: response.text)
                    return ImapCopyResult(response: response, copyUid: copyUid)
                }
            }
        }

        throw SessionError.timeout
    }

    public func move(_ set: String, to mailbox: String) throws -> ImapCopyResult {
        try ensureSelected()
        let command = client.send(.move(set, mailbox))
        try ensureWrite()
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let copyUid = ImapResponseCode.copyUid(from: response.text)
                    return ImapCopyResult(response: response, copyUid: copyUid)
                }
            }
        }

        throw SessionError.timeout
    }

    public func move(_ set: SequenceSet, to mailbox: String) throws -> ImapCopyResult {
        try move(set.description, to: mailbox)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String) throws -> ImapCopyResult {
        try ensureSelected()
        let command = client.send(.uidMove(set.description, mailbox))
        try ensureWrite()
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let copyUid = ImapResponseCode.copyUid(from: response.text)
                    return ImapCopyResult(response: response, copyUid: copyUid)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchSummaries(_ set: String, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        let previewSupported = capabilities?.supports("PREVIEW") ?? false
        let previewViaBody = request.items.contains(.previewText) && !previewSupported
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || previewViaBody
        let itemList = previewViaBody
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        let result = try fetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies)
        return result
    }

    public func fetchWithQresync(_ set: String, items: String) throws -> ImapFetchResult {
        try ensureSelected()
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchSummariesWithQresync(_ set: String, items: String, parseBodies: Bool) throws -> [MessageSummary] {
        try ensureSelected()
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var messages: [ImapLiteralMessage] = []
        var reads = 0

        while reads < maxReads {
            let batch = client.receiveWithLiterals()
            if batch.isEmpty {
                reads += 1
                continue
            }
            messages.append(contentsOf: batch)
            for message in batch {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                        let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                        let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                        return messages.compactMap { message in
                            guard let fetch = ImapFetchResponse.parse(message.line) else { return nil }
                            return MessageSummary.build(message: message, bodyMap: mapBySequence[fetch.sequence])
                        }
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchBodySections(_ set: String, items: String) throws -> [ImapFetchBodyMap] {
        let result = try fetchBodySectionsWithQresync(set, items: items)
        return result.bodies
    }

    public func fetchBodySectionsWithQresync(
        _ set: String,
        items: String,
        validity: UInt32? = nil
    ) throws -> ImapFetchBodyQresyncResult {
        try ensureSelected()
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var reads = 0
        var messages: [ImapLiteralMessage] = []
        var events: [ImapQresyncEvent] = []

        while reads < maxReads {
            let batch = client.receiveWithLiterals()
            if batch.isEmpty {
                reads += 1
                continue
            }

            for message in batch {
                messages.append(message)
                if let event = ingestSelectedState(from: message, validity: validity) {
                    events.append(event)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let bodies = ImapFetchBodyParser.parseMaps(messages)
                    return ImapFetchBodyQresyncResult(bodies: bodies, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidFetch(_ set: UniqueIdSet, items: String) throws -> [ImapFetchResponse] {
        let result = try uidFetchWithQresync(set, items: items)
        return result.responses
    }

    public func uidFetch(_ set: UniqueIdSet, request: FetchRequest) throws -> [ImapFetchResponse] {
        try uidFetch(set, items: request.imapItemList)
    }

    public func uidFetchSummaries(_ set: UniqueIdSet, request: FetchRequest, previewLength: Int = 512) throws -> [MessageSummary] {
        let previewSupported = capabilities?.supports("PREVIEW") ?? false
        let previewViaBody = request.items.contains(.previewText) && !previewSupported
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || previewViaBody
        let itemList = previewViaBody
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        let result = try uidFetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies)
        return result
    }

    public func uidFetchWithQresync(_ set: UniqueIdSet, items: String) throws -> ImapFetchResult {
        try ensureSelected()
        let command = client.send(.uidFetch(set.description, items))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidFetchSummariesWithQresync(_ set: UniqueIdSet, items: String, parseBodies: Bool) throws -> [MessageSummary] {
        try ensureSelected()
        let command = client.send(.uidFetch(set.description, items))
        try ensureWrite()
        var messages: [ImapLiteralMessage] = []
        var reads = 0

        while reads < maxReads {
            let batch = client.receiveWithLiterals()
            if batch.isEmpty {
                reads += 1
                continue
            }
            messages.append(contentsOf: batch)
            for message in batch {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                        let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                        let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                        return messages.compactMap { message in
                            guard let fetch = ImapFetchResponse.parse(message.line) else { return nil }
                            return MessageSummary.build(message: message, bodyMap: mapBySequence[fetch.sequence])
                        }
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidStore(_ set: UniqueIdSet, data: String) throws -> [ImapFetchResponse] {
        let result = try uidStoreWithQresync(set, data: data)
        return result.responses
    }

    public func uidStoreResult(_ set: UniqueIdSet, data: String) throws -> ImapStoreResult {
        let result = try uidStoreWithQresync(set, data: data)
        return ImapStoreResult(fetchResult: result)
    }

    public func uidStoreWithQresync(_ set: UniqueIdSet, data: String) throws -> ImapFetchResult {
        try ensureSelected()
        let command = client.send(.uidStore(set.description, data))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchAttributes(_ set: String, items: String) throws -> [ImapFetchAttributes] {
        let responses = try fetch(set, items: items)
        return responses.compactMap(ImapFetchAttributes.parse)
    }

    public func fetchAttributes(_ set: String, request: FetchRequest) throws -> [ImapFetchAttributes] {
        try fetchAttributes(set, items: request.imapItemList)
    }

    public func status(mailbox: String, items: [String]) throws -> ImapStatusResponse {
        try ensureAuthenticated()
        let command = client.send(.status(mailbox, items: items))
        try ensureWrite()
        var result: ImapStatusResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                _ = ingestSelectedState(from: message)
                if let status = ImapStatusResponse.parse(message) {
                    result = status
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    if let result {
                        if selectedMailbox == mailbox {
                            selectedState.apply(status: result)
                        }
                        return result
                    }
                    throw SessionError.imapError(status: response.status, text: "STATUS response missing")
                }
            }
        }

        throw SessionError.timeout
    }

    public func notify(arguments: String) throws -> ImapResponse {
        try ensureAuthenticated()
        let command = client.send(.notify(arguments))
        try ensureWrite()
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return response
                }
            }
        }

        throw SessionError.timeout
    }

    public func compress(algorithm: String = "DEFLATE") throws -> ImapResponse {
        let current = ImapSessionState(client.state)
        switch current {
        case .connected, .authenticated:
            break
        case .selected:
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        case .disconnected, .authenticating:
            throw SessionError.invalidImapState(expected: .connected, actual: current)
        }

        let normalized = algorithm.uppercased()
        guard let caps = client.capabilities,
              caps.rawTokens.contains(where: { $0.uppercased() == "COMPRESS=\(normalized)" }) else {
            throw SessionError.compressionNotSupported
        }
        guard let compressionTransport = transport as? CompressionTransport else {
            throw SessionError.compressionNotSupported
        }

        let command = client.send(.compress(normalized))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }

        if response.isOk {
            try compressionTransport.startCompression(algorithm: normalized)
            return response
        }

        if response.text.uppercased().contains("COMPRESSIONACTIVE") {
            return response
        }

        throw SessionError.imapError(status: response.status, text: response.text)
    }

    public func startTls(validateCertificate: Bool = true) throws -> ImapResponse {
        guard let tlsTransport = transport as? StartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        let command = client.send(.starttls)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    public func startIdle() throws -> ImapResponse {
        try ensureSelected()
        let command = client.send(.idle)
        idleTag = command.tag
        try ensureWrite()
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response, case .continuation = response.kind {
                    return response
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    idleTag = nil
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }
        idleTag = nil
        throw SessionError.timeout
    }

    public func readIdleEvents(maxReads: Int? = nil) -> [ImapIdleEvent] {
        guard client.state == .selected else { return [] }
        let limit = maxReads ?? self.maxReads
        var reads = 0
        var events: [ImapIdleEvent] = []
        while reads < limit {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let event = ImapIdleEvent.parse(message.line) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                break
            }
        }
        return events
    }

    public func stopIdle() throws {
        try ensureSelected()
        guard let idleTag else {
            throw SessionError.imapError(status: .bad, text: "IDLE not active.")
        }
        client.sendLiteral(Array("DONE\r\n".utf8))
        try ensureWrite()
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == idleTag {
                    self.idleTag = nil
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return
                }
            }
        }
        self.idleTag = nil
        throw SessionError.timeout
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxReads: Int? = nil) -> [ImapQresyncEvent] {
        guard client.state == .selected else { return [] }
        let limit = maxReads ?? self.maxReads
        var reads = 0
        var events: [ImapQresyncEvent] = []
        while reads < limit {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let event = ingestSelectedState(from: message, validity: validity) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                break
            }
        }
        return events
    }

    private func waitForGreeting() -> ImapResponse? {
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response {
                    return response
                }
            }
        }
        return nil
    }

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }

    private func postAuthenticate() throws {
        if client.capabilities?.supports("NAMESPACE") == true {
            namespaces = try? namespace()
        }
        if let caps = client.capabilities {
            if caps.supports("SPECIAL-USE") {
                if let list = try? listSpecialUse(reference: "", mailbox: "*") {
                    specialUseMailboxes = list.filter { $0.specialUse != nil }
                }
            } else if caps.supports("XLIST") {
                if let list = try? xlist(reference: "", mailbox: "*") {
                    specialUseMailboxes = list.filter { $0.specialUse != nil }
                }
            }
        }
    }

    private func ensureAuthenticated() throws {
        let current = ImapSessionState(client.state)
        guard current == .authenticated || current == .selected else {
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        }
    }

    private func ensureSelected() throws {
        let current = ImapSessionState(client.state)
        guard current == .selected else {
            throw SessionError.invalidImapState(expected: .selected, actual: current)
        }
    }

    private func applySelectedState(_ state: inout ImapSelectedState, mailbox: String, from message: ImapLiteralMessage) {
        if let response = message.response {
            state.apply(response: response)
        } else if let response = ImapResponse.parse(message.line) {
            state.apply(response: response)
        }
        if let idle = ImapIdleEvent.parse(message.line) {
            state.apply(event: idle)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            state.apply(modSeq: modSeq)
        }
        if let fetch = ImapFetchResponse.parse(message.line),
           let attrs = ImapFetchAttributes.parse(message) {
            state.applyFetch(sequence: fetch.sequence, uid: attrs.uid, modSeq: attrs.modSeq)
        }
        if let status = ImapStatusResponse.parse(message), status.mailbox == mailbox {
            state.apply(status: status)
        }
        if let listStatus = ImapListStatusResponse.parse(message), listStatus.mailbox.name == mailbox {
            state.apply(listStatus: listStatus)
        }
        if let event = ImapQresyncEvent.parse(message, validity: state.uidValidity ?? 0) {
            state.apply(event: event)
        }
    }

    private func ingestSelectedState(from message: ImapLiteralMessage, validity: UInt32? = nil) -> ImapQresyncEvent? {
        if let response = message.response {
            selectedState.apply(response: response)
        } else if let response = ImapResponse.parse(message.line) {
            selectedState.apply(response: response)
        }
        if let idle = ImapIdleEvent.parse(message.line) {
            selectedState.apply(event: idle)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            selectedState.apply(modSeq: modSeq)
        }
        if let fetch = ImapFetchResponse.parse(message.line),
           let attrs = ImapFetchAttributes.parse(message) {
            selectedState.applyFetch(sequence: fetch.sequence, uid: attrs.uid, modSeq: attrs.modSeq)
        }
        if let status = ImapStatusResponse.parse(message),
           let selectedMailbox,
           status.mailbox == selectedMailbox {
            selectedState.apply(status: status)
        }
        if let listStatus = ImapListStatusResponse.parse(message),
           let selectedMailbox,
           listStatus.mailbox.name == selectedMailbox {
            selectedState.apply(listStatus: listStatus)
        }
        if let validity, validity > 0, selectedState.uidValidity == nil {
            selectedState.uidValidity = validity
        }
        let validity = validity ?? selectedState.uidValidity ?? 0
        if let event = ImapQresyncEvent.parse(message, validity: validity) {
            selectedState.apply(event: event)
            return event
        }
        return nil
    }
}

extension ImapSession: MailService {
    public typealias ConnectResponse = ImapResponse

    public var state: MailServiceState {
        switch client.state {
        case .disconnected:
            return .disconnected
        case .connected, .authenticating:
            return .connected
        case .authenticated, .selected:
            return .authenticated
        }
    }

    public var isConnected: Bool { client.isConnected }

    public var isAuthenticated: Bool {
        client.state == .authenticated || client.state == .selected
    }
}
