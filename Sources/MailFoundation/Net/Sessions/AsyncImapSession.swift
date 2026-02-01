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
// AsyncImapSession.swift
//
// Higher-level async IMAP session helpers.
//

import Foundation

/// Default timeout for IMAP operations in milliseconds (2 minutes, matching MailKit).
public let defaultImapTimeoutMs = 120_000

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapSession {
    private let client: AsyncImapClient
    private let transport: AsyncTransport
    private var idleTag: String?
    public private(set) var selectedMailbox: String?
    public private(set) var selectedState = ImapSelectedState()
    public private(set) var namespaces: ImapNamespaceResponse?
    public private(set) var specialUseMailboxes: [ImapMailbox] = []

    public var capabilities: ImapCapabilities? {
        get async {
            await client.capabilities
        }
    }

    private nonisolated func debugLog(_ message: String) {
        MailFoundationLogging.debug(.imapSession, message)
    }

    /// The timeout for network operations in milliseconds.
    ///
    /// Default is 120000 (2 minutes), matching MailKit's default.
    /// Set to `Int.max` for no timeout.
    public private(set) var timeoutMilliseconds: Int = defaultImapTimeoutMs

    /// Sets the timeout for network operations.
    ///
    /// - Parameter milliseconds: The timeout in milliseconds
    public func setTimeoutMilliseconds(_ milliseconds: Int) {
        timeoutMilliseconds = milliseconds
    }

    /// Sets the protocol logger for debugging IMAP communication.
    ///
    /// - Parameter logger: The protocol logger to use.
    public func setProtocolLogger(_ logger: sending ProtocolLoggerType) async {
        await client.setProtocolLogger(logger)
    }

    public init(transport: AsyncTransport, timeoutMilliseconds: Int = defaultImapTimeoutMs) {
        self.transport = transport
        self.client = AsyncImapClient(transport: transport)
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        timeoutMilliseconds: Int = defaultImapTimeoutMs
    ) throws -> AsyncImapSession {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncImapSession(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        proxy: ProxySettings,
        timeoutMilliseconds: Int = defaultImapTimeoutMs
    ) async throws -> AsyncImapSession {
        let transport = try await AsyncTransportFactory.make(host: host, port: port, backend: backend, proxy: proxy)
        return AsyncImapSession(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    @discardableResult
    public func connect() async throws -> ImapResponse? {
        try await withSessionTimeout {
            try await self.client.start()
            return await self.waitForGreeting()
        }
    }

    /// Connects with implicit TLS (for IMAPS on port 993).
    ///
    /// This method configures TLS before establishing the connection,
    /// which is required for IMAPS connections (typically port 993)
    /// where TLS is required from the start.
    ///
    /// - Parameter validateCertificate: Whether to validate the server's TLS certificate.
    /// - Returns: The server's greeting response, or `nil` if none.
    /// - Throws: An error if the transport does not support implicit TLS or the connection fails.
    @discardableResult
    public func connectSecure(validateCertificate: Bool = true) async throws -> ImapResponse? {
        return try await withSessionTimeout {
            try await self.client.startSecure(validateCertificate: validateCertificate)
            return await self.waitForGreeting()
        }
    }

    public func disconnect() async {
        _ = try? await client.logout()
        await client.stop()
        selectedMailbox = nil
        selectedState = ImapSelectedState()
        namespaces = nil
        specialUseMailboxes = []
        idleTag = nil
    }

    public func capability() async throws -> ImapResponse? {
        try await withSessionTimeout {
            try await self.client.capability()
        }
    }

    public func login(user: String, password: String) async throws -> ImapResponse? {
        try await withSessionTimeout {
            let initialCapabilitiesVersion = await self.client.capabilitiesVersion
            let response = try await self.client.login(user: user, password: password)
            if response?.isOk == true {
                if await self.client.capabilitiesVersion == initialCapabilitiesVersion {
                    _ = try? await self.capability()
                }
                await self.postAuthenticate()
            }
            return response
        }
    }

    /// Authenticates using SASL mechanism
    public func authenticate(_ auth: ImapAuthentication) async throws -> ImapResponse? {
        try await withSessionTimeout {
            let response = try await self.client.authenticate(auth)
            if response?.isOk == true {
                await self.postAuthenticate()
            }
            return response
        }
    }

    /// Authenticates using XOAUTH2 with an OAuth access token
    public func authenticateXoauth2(user: String, accessToken: String) async throws -> ImapResponse? {
        let auth = ImapSasl.xoauth2(username: user, accessToken: accessToken)
        return try await authenticate(auth)
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
    ) async throws -> ImapResponse? {
        let availableMechanisms: [String]
        if let mechanisms {
            availableMechanisms = mechanisms
        } else {
            if await client.capabilities == nil {
                _ = try? await capability()
            }
            availableMechanisms = await client.capabilities?.saslMechanisms() ?? []
        }

        let resolvedChannelBinding: ScramChannelBinding?
        if let channelBinding {
            resolvedChannelBinding = channelBinding
        } else if let tlsTransport = transport as? AsyncStartTlsTransport {
            resolvedChannelBinding = await tlsTransport.scramChannelBinding
        } else {
            resolvedChannelBinding = nil
        }

        guard let authentication = ImapSasl.chooseAuthentication(
            username: user,
            password: password,
            mechanisms: availableMechanisms,
            host: host,
            channelBinding: resolvedChannelBinding
        ) else {
            throw SessionError.imapError(status: .no, text: "No supported SASL mechanisms.")
        }
        return try await authenticate(authentication)
    }

    public func noop() async throws -> ImapResponse? {
        try await withSessionTimeout {
            let command = try await self.client.send(.noop)
            var emptyReads = 0
            while emptyReads < 10 {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    private func withSessionTimeout<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withTimeout(milliseconds: timeoutMilliseconds, operation: operation)
    }

    private func postAuthenticate() async {
        if await client.capabilities?.supports("NAMESPACE") == true {
            namespaces = try? await namespace()
        }
        if let caps = await client.capabilities {
            if caps.supports("SPECIAL-USE") {
                if let list = try? await listSpecialUse(reference: "", mailbox: "*") {
                    specialUseMailboxes = list.filter { $0.specialUse != nil }
                }
            } else if caps.supports("XLIST") {
                if let list = try? await xlist(reference: "", mailbox: "*") {
                    specialUseMailboxes = list.filter { $0.specialUse != nil }
                }
            }
        }
    }

    public func enable(_ capabilities: [String], maxEmptyReads: Int = 10) async throws -> [String] {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.enable(capabilities))
            var enabled: [String] = []
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.select(mailbox))
            self.debugLog("[select] sent command tag=\(command.tag) for mailbox=\(mailbox)")
            var emptyReads = 0
            var nextState = ImapSelectedState()

            while true {
                try Task.checkCancellation()
                self.debugLog("[select] calling nextMessages(), emptyReads=\(emptyReads)")
                let messages = await self.client.nextMessages()
                self.debugLog("[select] nextMessages() returned \(messages.count) messages")
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        self.debugLog("[select] connection closed")
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    if emptyReads > 10 {
                        self.debugLog("[select] too many empty reads, throwing timeout")
                        throw SessionError.timeout
                    }
                    continue
                }
                emptyReads = 0
                for message in messages {
                    await self.applySelectedState(&nextState, mailbox: mailbox, from: message)
                    self.debugLog("[select] checking message: hasResponse=\(message.response != nil)")
                    if let response = message.response {
                        self.debugLog("[select] response kind=\(response.kind), looking for tag=\(command.tag)")
                        if case let .tagged(tag) = response.kind {
                            self.debugLog("[select] found tagged response: tag=\(tag), matches=\(tag == command.tag)")
                            if tag == command.tag {
                                guard response.isOk else {
                                    self.debugLog("[select] response is not OK, throwing error")
                                    throw SessionError.imapError(status: response.status, text: response.text)
                                }
                                await self.updateSelectedState(mailbox: mailbox, state: nextState)
                                return response
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateSelectedState(mailbox: String, state: ImapSelectedState) async {
        self.selectedMailbox = mailbox
        self.selectedState = state
    }

    public func examine(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.examine(mailbox))
            var emptyReads = 0
            var nextState = ImapSelectedState()

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    await self.applySelectedState(&nextState, mailbox: mailbox, from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        guard response.isOk else {
                            throw SessionError.imapError(status: response.status, text: response.text)
                        }
                        await self.updateSelectedState(mailbox: mailbox, state: nextState)
                        return response
                    }
                }
            }
            throw SessionError.timeout
        }
    }

    public func close() async throws -> ImapResponse? {
        try await ensureSelected()
        return try await withSessionTimeout {
            let response = try await self.client.close()
            if response?.isOk == true {
                await self.clearSelectedState()
            }
            return response
        }
    }

    private func clearSelectedState() async {
        self.selectedMailbox = nil
        self.selectedState = ImapSelectedState()
    }

    public func check(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.check)
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func expunge(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.expunge)
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
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
    }

    public func create(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.create(mailbox))
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func delete(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.delete(mailbox))
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func rename(mailbox: String, newName: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.rename(mailbox, newName))
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func subscribe(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.subscribe(mailbox))
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func unsubscribe(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.unsubscribe(mailbox))
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
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
    }

    public func list(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await listResponses(reference: reference, mailbox: mailbox, maxEmptyReads: maxEmptyReads)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func listExtended(
        reference: String,
        mailbox: String,
        returns: [ImapListReturnOption] = [],
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailbox] {
        let responses = try await listExtendedResponses(
            reference: reference,
            mailbox: mailbox,
            returns: returns,
            maxEmptyReads: maxEmptyReads
        )
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func listResponses(
        reference: String,
        mailbox: String,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await listResponses(command: .list(reference, mailbox), maxEmptyReads: maxEmptyReads)
    }

    public func listExtendedResponses(
        reference: String,
        mailbox: String,
        returns: [ImapListReturnOption] = [],
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await listResponses(
            command: .listExtended(reference, mailbox, returns: returns),
            maxEmptyReads: maxEmptyReads
        )
    }

    private func listResponses(
        command: ImapCommandKind,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(command)
            var responses: [ImapMailboxListResponse] = []
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
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
    }

    private func listSpecialUse(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await listResponses(
            command: .listSpecialUse(reference, mailbox),
            maxEmptyReads: maxEmptyReads
        )
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    private func xlist(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await listResponses(
            command: .xlist(reference, mailbox),
            maxEmptyReads: maxEmptyReads
        )
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func lsub(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await lsubResponses(reference: reference, mailbox: mailbox, maxEmptyReads: maxEmptyReads)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func lsubResponses(
        reference: String,
        mailbox: String,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.lsub(reference, mailbox))
            var responses: [ImapMailboxListResponse] = []
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
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
    }

    public func listStatus(
        reference: String,
        mailbox: String,
        items: [String] = ["MESSAGES", "UNSEEN", "UIDNEXT", "UIDVALIDITY"],
        maxEmptyReads: Int = 10
    ) async throws -> [ImapListStatusResponse] {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let normalizedItems = items.isEmpty ? ["MESSAGES"] : items
            let command = try await self.client.send(.listStatus(reference, mailbox, items: normalizedItems))
            var responses: [ImapListStatusResponse] = []
            var mailboxMap: [String: ImapMailbox] = [:]
            var statusMap: [String: [String: Int]] = [:]
            var seen: Set<String> = []
            var emptyReads = 0

            func appendStatus(name: String, mailbox: ImapMailbox, items: [String: Int]) {
                guard !seen.contains(name) else { return }
                responses.append(ImapListStatusResponse(mailbox: mailbox, statusItems: items))
                seen.insert(name)
            }

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
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
    }

    public func capabilities() async -> ImapCapabilities? {
        await client.capabilities
    }

    public func search(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.search(criteria))
            var result = ImapSearchResponse(ids: [], isUid: false)
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let esearch = ImapESearchResponse.parse(message.line) {
                        result = ImapSearchResponse(esearch: esearch, defaultIsUid: false)
                    } else if let search = ImapSearchResponse.parse(message.line) {
                        result = ImapSearchResponse(ids: search.ids, isUid: false)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return result
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func search(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await search(query.optimized().serialize(), maxEmptyReads: maxEmptyReads)
    }

    public func sort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        try await ensureSelected()
        try await ImapSort.validateCapabilities(orderBy: orderBy, capabilities: await client.capabilities)
        let kind = try ImapCommandKind.sort(query, orderBy: orderBy, charset: charset)
        
        return try await withSessionTimeout {
            let command = try await self.client.send(kind)
            var result = ImapSearchResponse(ids: [], isUid: false)
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let esearch = ImapESearchResponse.parse(message.line) {
                        result = ImapSearchResponse(esearch: esearch, defaultIsUid: false)
                    } else if let search = ImapSearchResponse.parse(message.line) {
                        result = ImapSearchResponse(ids: search.ids, isUid: false)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return result
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidSearch(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidSearch(criteria))
            var result = ImapSearchResponse(ids: [], isUid: true)
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let esearch = ImapESearchResponse.parse(message.line) {
                        result = ImapSearchResponse(esearch: esearch, defaultIsUid: true)
                    } else if let search = ImapSearchResponse.parse(message.line) {
                        result = ImapSearchResponse(ids: search.ids, isUid: true)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return result
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidSearch(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await uidSearch(query.optimized().serialize(), maxEmptyReads: maxEmptyReads)
    }

    public func uidSort(
        _ orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8",
        maxEmptyReads: Int = 10
    ) async throws -> ImapSearchResponse {
        try await ensureSelected()
        try await ImapSort.validateCapabilities(orderBy: orderBy, capabilities: await client.capabilities)
        let kind = try ImapCommandKind.uidSort(query, orderBy: orderBy, charset: charset)
        
        return try await withSessionTimeout {
            let command = try await self.client.send(kind)
            var result = ImapSearchResponse(ids: [], isUid: true)
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let esearch = ImapESearchResponse.parse(message.line) {
                        result = ImapSearchResponse(esearch: esearch, defaultIsUid: true)
                    } else if let search = ImapSearchResponse.parse(message.line) {
                        result = ImapSearchResponse(ids: search.ids, isUid: true)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return result
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func status(mailbox: String, items: [String], maxEmptyReads: Int = 10) async throws -> ImapStatusResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.status(mailbox, items: items))
            var result: ImapStatusResponse?
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let status = ImapStatusResponse.parse(message) {
                        result = status
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk, let result {
                            await self.applyStatusToSelected(mailbox: mailbox, status: result)
                            return result
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func notify(arguments: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        if await client.capabilities == nil {
            _ = try? await capability()
        }
        guard await client.capabilities?.supports("NOTIFY") == true else {
            throw SessionError.notifyNotSupported
        }
        return try await withSessionTimeout {
            let command = try await self.client.send(.notify(arguments))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
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
    }

    public func compress(algorithm: String = "DEFLATE", maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let current = ImapSessionState(await client.state)
        switch current {
        case .connected, .authenticated:
            break
        case .selected:
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        case .disconnected, .authenticating:
            throw SessionError.invalidImapState(expected: .connected, actual: current)
        }

        let normalized = algorithm.uppercased()
        guard let caps = await client.capabilities,
              caps.rawTokens.contains(where: { $0.uppercased() == "COMPRESS=\(normalized)" }) else {
            throw SessionError.compressionNotSupported
        }
        guard let compressionTransport = transport as? AsyncCompressionTransport else {
            throw SessionError.compressionNotSupported
        }

        return try await withSessionTimeout {
            let command = try await self.client.send(.compress(normalized))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            try await compressionTransport.startCompression(algorithm: normalized)
                            return response
                        }
                        if response.text.uppercased().contains("COMPRESSIONACTIVE") {
                            return response
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    private func applyStatusToSelected(mailbox: String, status: ImapStatusResponse) {
        if selectedMailbox == mailbox {
            selectedState.apply(status: status)
        }
    }

    public func fetch(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        try await ensureSelected()
        let result = try await fetchWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func fetch(_ set: String, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        try await fetch(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
    }

    public func namespace(maxEmptyReads: Int = 10) async throws -> ImapNamespaceResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.namespace)
            var emptyReads = 0
            var response: ImapNamespaceResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapNamespaceResponse.parse(message.line) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func getQuota(_ root: String, maxEmptyReads: Int = 10) async throws -> ImapQuotaResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.getQuota(root))
            var emptyReads = 0
            var response: ImapQuotaResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapQuotaResponse.parse(message.line) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func getQuotaRoot(_ mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapQuotaRootResult {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.getQuotaRoot(mailbox))
            var emptyReads = 0
            var quotaRoot: ImapQuotaRootResponse?
            var quotas: [ImapQuotaResponse] = []

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsedRoot = ImapQuotaRootResponse.parse(message.line) {
                        quotaRoot = parsedRoot
                    }
                    if let parsedQuota = ImapQuotaResponse.parse(message.line) {
                        quotas.append(parsedQuota)
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return ImapQuotaRootResult(quotaRoot: quotaRoot, quotas: quotas)
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func getAcl(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapAclResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.getAcl(mailbox))
            var emptyReads = 0
            var response: ImapAclResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapAclResponse.parse(message.line) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func setAcl(
        mailbox: String,
        identifier: String,
        rights: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.setAcl(mailbox, identifier: identifier, rights: rights))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return tagged
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func listRights(
        mailbox: String,
        identifier: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapListRightsResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.listRights(mailbox, identifier: identifier))
            var emptyReads = 0
            var response: ImapListRightsResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapListRightsResponse.parse(message.line) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func myRights(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapMyRightsResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.myRights(mailbox))
            var emptyReads = 0
            var response: ImapMyRightsResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapMyRightsResponse.parse(message.line) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func getMetadata(
        mailbox: String,
        options: ImapMetadataOptions? = nil,
        entries: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapMetadataResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.getMetadata(mailbox, options: options, entries: entries))
            var emptyReads = 0
            var response: ImapMetadataResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapMetadataResponse.parse(message) {
                        response = parsed
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func setMetadata(
        mailbox: String,
        entries: [ImapMetadataEntry],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.setMetadata(mailbox, entries: entries))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return tagged
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func getAnnotation(
        mailbox: String,
        entries: [String],
        attributes: [String],
        maxEmptyReads: Int = 10
    ) async throws -> ImapAnnotationResult? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.getAnnotation(mailbox, entries: entries, attributes: attributes))
            var emptyReads = 0
            var mailboxName: String?
            var entriesResult: [ImapAnnotationEntry] = []

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let parsed = ImapAnnotationResponse.parse(message) {
                        mailboxName = parsed.mailbox
                        entriesResult.append(parsed.entry)
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            guard let mailboxName else { return nil }
                            return ImapAnnotationResult(mailbox: mailboxName, entries: entriesResult)
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func setAnnotation(
        mailbox: String,
        entry: String,
        attributes: [ImapAnnotationAttribute],
        maxEmptyReads: Int = 10
    ) async throws -> ImapResponse {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.setAnnotation(mailbox, entry: entry, attributes: attributes))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return tagged
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func id(_ parameters: [String: String?]? = nil, maxEmptyReads: Int = 10) async throws -> ImapIdResponse? {
        return try await withSessionTimeout {
            let command = try await self.client.send(.id(ImapId.buildArguments(parameters)))
            var emptyReads = 0
            var response: ImapIdResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let idResponse = ImapIdResponse.parse(message.line) {
                        response = idResponse
                    }
                    if let tagged = message.response, case let .tagged(tag) = tagged.kind, tag == command.tag {
                        if tagged.isOk {
                            return response
                        }
                        throw SessionError.imapError(status: tagged.status, text: tagged.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func copy(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.copy(set, mailbox))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let copyUid = ImapResponseCode.copyUid(from: response.text)
                            return ImapCopyResult(response: response, copyUid: copyUid)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func copy(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await copy(set.description, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidCopy(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidCopy(set.description, mailbox))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let copyUid = ImapResponseCode.copyUid(from: response.text)
                            return ImapCopyResult(response: response, copyUid: copyUid)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func move(_ set: String, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.move(set, mailbox))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let copyUid = ImapResponseCode.copyUid(from: response.text)
                            return ImapCopyResult(response: response, copyUid: copyUid)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func move(_ set: SequenceSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await move(set.description, to: mailbox, maxEmptyReads: maxEmptyReads)
    }

    public func uidMove(_ set: UniqueIdSet, to mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapCopyResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidMove(set.description, mailbox))
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let copyUid = ImapResponseCode.copyUid(from: response.text)
                            return ImapCopyResult(response: response, copyUid: copyUid)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func fetchSummaries(
        _ set: String,
        request: FetchRequest,
        previewLength: Int = 512,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        let previewSupported = await capabilities?.supports("PREVIEW") ?? false
        let previewViaBody = request.items.contains(.previewText) && !previewSupported
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || previewViaBody
        let itemList = previewViaBody
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        return try await fetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies, maxEmptyReads: maxEmptyReads)
    }

    public func fetchWithQresync(
        _ set: String,
        items: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.fetch(set, items))
            var results: [ImapFetchResponse] = []
            var events: [ImapQresyncEvent] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let event = await self.ingestSelectedState(from: message) {
                        events.append(event)
                    }
                    if let fetch = ImapFetchResponse.parse(message.line) {
                        results.append(fetch)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return ImapFetchResult(responses: results, qresyncEvents: events)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func fetchSummariesWithQresync(
        _ set: String,
        items: String,
        parseBodies: Bool,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.fetch(set, items))
            var messages: [ImapLiteralMessage] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let batch = await self.client.nextMessages()
                if batch.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                messages.append(contentsOf: batch)
                for message in batch {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                            let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                            return messages.compactMap { message in
                                guard let fetch = ImapFetchResponse.parse(message.line) else { return nil }
                                return MessageSummary.build(message: message, bodyMap: mapBySequence[fetch.sequence])
                            }
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func fetchBodySections(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchBodyMap] {
        let result = try await fetchBodySectionsWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.bodies
    }

    public func fetchBodySectionsWithQresync(
        _ set: String,
        items: String,
        validity: UInt32? = nil,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchBodyQresyncResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.fetch(set, items))
            var messages: [ImapLiteralMessage] = []
            var events: [ImapQresyncEvent] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let batch = await self.client.nextMessages()
                if batch.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    // Don't count as empty read if decoder is still processing a literal
                    if await !self.client.hasPendingData {
                        emptyReads += 1
                    }
                    continue
                }
                emptyReads = 0
                for message in batch {
                    messages.append(message)
                    if let event = await self.ingestSelectedState(from: message, validity: validity) {
                        events.append(event)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let bodies = ImapFetchBodyParser.parseMaps(messages)
                            return ImapFetchBodyQresyncResult(bodies: bodies, qresyncEvents: events)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidFetchBodySections(_ set: UniqueIdSet, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchBodyMap] {
        let result = try await uidFetchBodySectionsWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.bodies
    }

    public func uidFetchBodySectionsWithQresync(
        _ set: UniqueIdSet,
        items: String,
        validity: UInt32? = nil,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchBodyQresyncResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidFetch(set.description, items))
            var messages: [ImapLiteralMessage] = []
            var events: [ImapQresyncEvent] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let batch = await self.client.nextMessages()
                if batch.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    // Don't count as empty read if decoder is still processing a literal
                    if await !self.client.hasPendingData {
                        emptyReads += 1
                    }
                    continue
                }
                emptyReads = 0
                for message in batch {
                    messages.append(message)
                    if let event = await self.ingestSelectedState(from: message, validity: validity) {
                        events.append(event)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let bodies = ImapFetchBodyParser.parseMaps(messages)
                            return ImapFetchBodyQresyncResult(bodies: bodies, qresyncEvents: events)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidFetch(_ set: UniqueIdSet, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let result = try await uidFetchWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func uidFetch(_ set: UniqueIdSet, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        try await uidFetch(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
    }

    public func uidFetchSummaries(
        _ set: UniqueIdSet,
        request: FetchRequest,
        previewLength: Int = 512,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        let previewSupported = await capabilities?.supports("PREVIEW") ?? false
        let previewViaBody = request.items.contains(.previewText) && !previewSupported
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || previewViaBody
        let itemList = previewViaBody
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        return try await uidFetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies, maxEmptyReads: maxEmptyReads)
    }

    public func uidFetchWithQresync(
        _ set: UniqueIdSet,
        items: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidFetch(set.description, items))
            var results: [ImapFetchResponse] = []
            var events: [ImapQresyncEvent] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let event = await self.ingestSelectedState(from: message) {
                        events.append(event)
                    }
                    if let fetch = ImapFetchResponse.parse(message.line) {
                        results.append(fetch)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return ImapFetchResult(responses: results, qresyncEvents: events)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidFetchSummariesWithQresync(
        _ set: UniqueIdSet,
        items: String,
        parseBodies: Bool,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidFetch(set.description, items))
            var messages: [ImapLiteralMessage] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let batch = await self.client.nextMessages()
                if batch.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                messages.append(contentsOf: batch)
                for message in batch {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                            let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                            return messages.compactMap { message in
                                guard let fetch = ImapFetchResponse.parse(message.line) else { return nil }
                                return MessageSummary.build(message: message, bodyMap: mapBySequence[fetch.sequence])
                            }
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func uidStore(_ set: UniqueIdSet, data: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let result = try await uidStoreWithQresync(set, data: data, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func uidStoreResult(
        _ set: UniqueIdSet,
        data: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapStoreResult {
        let result = try await uidStoreWithQresync(set, data: data, maxEmptyReads: maxEmptyReads)
        return ImapStoreResult(fetchResult: result)
    }

    public func uidStoreWithQresync(
        _ set: UniqueIdSet,
        data: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
        return try await withSessionTimeout {
            let command = try await self.client.send(.uidStore(set.description, data))
            var results: [ImapFetchResponse] = []
            var events: [ImapQresyncEvent] = []
            var emptyReads = 0

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let event = await self.ingestSelectedState(from: message) {
                        events.append(event)
                    }
                    if let fetch = ImapFetchResponse.parse(message.line) {
                        results.append(fetch)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        if response.isOk {
                            return ImapFetchResult(responses: results, qresyncEvents: events)
                        }
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }

            throw SessionError.timeout
        }
    }

    public func fetchAttributes(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchAttributes] {
        let responses = try await fetch(set, items: items, maxEmptyReads: maxEmptyReads)
        return responses.compactMap(ImapFetchAttributes.parse)
    }

    public func fetchAttributes(_ set: String, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchAttributes] {
        try await fetchAttributes(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
    }

    public func startTls(validateCertificate: Bool = true, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        return try await withSessionTimeout {
            let command = try await self.client.send(.starttls)
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        guard response.isOk else {
                            throw SessionError.imapError(status: response.status, text: response.text)
                        }
                        try await tlsTransport.startTLS(validateCertificate: validateCertificate)
                        return response
                    }
                }
            }
            throw SessionError.timeout
        }
    }

    public func startIdle(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureSelected()
        if await client.capabilities == nil {
            _ = try? await capability()
        }
        guard await client.capabilities?.supports("IDLE") == true else {
            throw SessionError.idleNotSupported
        }
        return try await withSessionTimeout {
            let command = try await self.client.send(.idle)
            await self.setIdleTag(command.tag)
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let response = message.response, case .continuation = response.kind {
                        return response
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        await self.setIdleTag(nil)
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                }
            }
            await self.setIdleTag(nil)
            throw SessionError.timeout
        }
    }

    public func readIdleEvents(maxEmptyReads: Int = 10) async throws -> [ImapIdleEvent] {
        try await ensureSelected()
        return try await withSessionTimeout {
            var emptyReads = 0
            var events: [ImapIdleEvent] = []
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let event = ImapIdleEvent.parse(message.line) {
                        events.append(event)
                    }
                }
                if !events.isEmpty {
                    return events
                }
            }
            throw SessionError.timeout
        }
    }

    public func stopIdle() async throws {
        try await ensureSelected()
        guard let idleTag else {
            throw SessionError.imapError(status: .bad, text: "IDLE not active.")
        }
        _ = try await withSessionTimeout {
            try await self.client.sendLiteral(Array("DONE\r\n".utf8))
            var emptyReads = 0
            while emptyReads < 10 {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == idleTag {
                        await self.setIdleTag(nil)
                        guard response.isOk else {
                            throw SessionError.imapError(status: response.status, text: response.text)
                        }
                        return
                    }
                }
            }
            await self.setIdleTag(nil)
            throw SessionError.timeout
        }
    }

    private func setIdleTag(_ tag: String?) {
        idleTag = tag
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxEmptyReads: Int = 10) async throws -> [ImapQresyncEvent] {
        try await ensureSelected()
        return try await withSessionTimeout {
            var emptyReads = 0
            var events: [ImapQresyncEvent] = []
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    if let event = await self.ingestSelectedState(from: message, validity: validity) {
                        events.append(event)
                    }
                }
                if !events.isEmpty {
                    return events
                }
            }
            throw SessionError.timeout
        }
    }

    private func ensureAuthenticated() async throws {
        let current = ImapSessionState(await client.state)
        guard current == .authenticated || current == .selected else {
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        }
    }

    private func ensureSelected() async throws {
        let current = ImapSessionState(await client.state)
        guard current == .selected else {
            throw SessionError.invalidImapState(expected: .selected, actual: current)
        }
    }

    private func applySelectedState(_ state: inout ImapSelectedState, mailbox: String, from message: ImapLiteralMessage) async {
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

    private func ingestSelectedState(from message: ImapLiteralMessage, validity: UInt32? = nil) async -> ImapQresyncEvent? {
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

    private func waitForGreeting() async -> ImapResponse? {
        while true {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                return nil
            }
            for message in messages {
                if let response = message.response {
                    return response
                }
            }
        }
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension AsyncImapSession: AsyncMailService {
    public typealias ConnectResponse = ImapResponse?

    public var state: MailServiceState {
        get async {
            let clientState = await client.state
            switch clientState {
            case .disconnected:
                return .disconnected
            case .connected, .authenticating:
                return .connected
            case .authenticated, .selected:
                return .authenticated
            }
        }
    }

    public var isConnected: Bool {
        get async {
            let clientState = await client.state
            return clientState != .disconnected
        }
    }

    public var isAuthenticated: Bool {
        get async {
            let clientState = await client.state
            return clientState == .authenticated || clientState == .selected
        }
    }
}
