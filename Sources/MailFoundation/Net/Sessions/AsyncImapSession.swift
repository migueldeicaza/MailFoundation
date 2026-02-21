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

private enum AsyncImapSessionCommandContext {
    @TaskLocal static var token: UUID?
}

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapSession {
    private enum CommandAccessMode {
        case exclusive
        case pipeline
    }

    private struct QueuedCommandWaiter {
        let id: UUID
        let mode: CommandAccessMode
        let continuation: CheckedContinuation<UUID, Error>
    }

    private struct AutoPipelineRequest {
        let id: UUID
        let kind: ImapCommandKind
        let maxEmptyReads: Int
        let continuation: CheckedContinuation<ImapPipelineResult, Error>
        var tag: String?
        var messages: [ImapLiteralMessage]
    }

    private let client: AsyncImapClient
    private let transport: AsyncTransport
    private var idleTag: String?
    private var activeCommandToken: UUID?
    private var activeCommandMode: CommandAccessMode?
    private var activeCommandHolders = 0
    private var queuedCommandWaiters: [QueuedCommandWaiter] = []
    private var autoPipelineOrder: [UUID] = []
    private var autoPipelineRequests: [UUID: AutoPipelineRequest] = [:]
    private var autoPipelineTagMap: [String: UUID] = [:]
    private var autoPipelineDriverTask: Task<Void, Never>?
    private var pendingIdleEvents: [ImapIdleEvent] = []
    private var pendingQresyncEvents: [ImapQresyncEvent] = []
    public private(set) var selectedMailbox: String?
    public private(set) var selectedState = ImapSelectedState()
    public private(set) var namespaces: ImapNamespaceResponse?
    public private(set) var specialUseMailboxes: [ImapMailbox] = []

    public var capabilities: ImapCapabilities? {
        get async {
            await client.capabilities
        }
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
            let greeting = await self.waitForGreeting()
            if greeting == nil, await self.client.isDisconnected {
                throw SessionError.connectionClosed(message: "Connection closed by server.")
            }
            return try self.validateGreeting(greeting)
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
            let greeting = await self.waitForGreeting()
            if greeting == nil, await self.client.isDisconnected {
                throw SessionError.connectionClosed(message: "Connection closed by server.")
            }
            return try self.validateGreeting(greeting)
        }
    }

    public func disconnect() async {
        failAllAutoPipelineRequests(with: SessionError.connectionClosed(message: "Connection closed by server."))
        autoPipelineDriverTask?.cancel()
        autoPipelineDriverTask = nil
        _ = try? await client.logout()
        await client.stop()
        selectedMailbox = nil
        selectedState = ImapSelectedState()
        pendingIdleEvents = []
        pendingQresyncEvents = []
        namespaces = nil
        specialUseMailboxes = []
        idleTag = nil
        activeCommandToken = nil
        activeCommandMode = nil
        activeCommandHolders = 0
        queuedCommandWaiters = []
    }

    public func capability() async throws -> ImapResponse? {
        try await ensureIdleNotActive()
        return try await withSessionTimeout {
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
            do {
                let response = try await self.client.authenticate(auth)
                guard let response else {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    try await self.throwTimeoutOrConnectionClosed()
                }
                if response.isOk {
                    await self.postAuthenticate()
                }
                return response
            } catch AsyncTransportError.connectionFailed {
                throw SessionError.connectionClosed(message: "Connection closed by server.")
            }
        }
    }

    private func throwConnectionClosedIfDisconnected() async throws {
        if await client.isDisconnected {
            throw SessionError.connectionClosed(message: "Connection closed by server.")
        }
    }

    private func timeoutOrConnectionClosed() async -> SessionError {
        if await client.isDisconnected {
            return .connectionClosed(message: "Connection closed by server.")
        }
        return .timeout
    }

    private func throwTimeoutOrConnectionClosed() async throws -> Never {
        throw await timeoutOrConnectionClosed()
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
        try await ensureIdleNotActive()
        return try await withSessionTimeout {
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
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    private func withSessionTimeout<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withCommandAccess(mode: .exclusive) {
            try await withTimeout(milliseconds: self.timeoutMilliseconds, operation: operation)
        }
    }

    private func withPipelinedCommand<T: Sendable>(
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withCommandAccess(mode: .pipeline, operation)
    }

    private func withCommandAccess<T: Sendable>(
        mode: CommandAccessMode,
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if let taskToken = AsyncImapSessionCommandContext.token, activeCommandToken == taskToken {
            return try await operation()
        }

        let token: UUID
        if let activeToken = activeCommandToken {
            if activeCommandMode == .pipeline && mode == .pipeline {
                activeCommandHolders += 1
                token = activeToken
            } else {
                token = try await waitForQueuedCommandToken(mode: mode)
            }
        } else {
            token = UUID()
            activeCommandToken = token
            activeCommandMode = mode
            activeCommandHolders = 1
        }

        defer {
            releaseCommandToken(token)
        }

        return try await AsyncImapSessionCommandContext.$token.withValue(token) {
            try await operation()
        }
    }

    private func waitForQueuedCommandToken(mode: CommandAccessMode) async throws -> UUID {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID, Error>) in
                queuedCommandWaiters.append(QueuedCommandWaiter(id: waiterID, mode: mode, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelQueuedCommandWaiter(waiterID) }
        }
    }

    private func cancelQueuedCommandWaiter(_ waiterID: UUID) {
        guard let index = queuedCommandWaiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = queuedCommandWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
        if activeCommandToken == nil {
            grantQueuedCommandWaiters()
        }
    }

    private func releaseCommandToken(_ token: UUID) {
        guard activeCommandToken == token else { return }
        activeCommandHolders = max(0, activeCommandHolders - 1)
        guard activeCommandHolders == 0 else { return }

        activeCommandToken = nil
        activeCommandMode = nil
        grantQueuedCommandWaiters()
    }

    private func grantQueuedCommandWaiters() {
        guard activeCommandToken == nil, !queuedCommandWaiters.isEmpty else { return }
        let mode = queuedCommandWaiters[0].mode
        let token = UUID()
        activeCommandToken = token
        activeCommandMode = mode
        activeCommandHolders = 0

        if mode == .pipeline {
            while !queuedCommandWaiters.isEmpty, queuedCommandWaiters[0].mode == .pipeline {
                let waiter = queuedCommandWaiters.removeFirst()
                activeCommandHolders += 1
                waiter.continuation.resume(returning: token)
            }
        } else {
            let waiter = queuedCommandWaiters.removeFirst()
            activeCommandHolders = 1
            waiter.continuation.resume(returning: token)
        }
    }

    private func postAuthenticate() async {
        if await client.capabilities?.supports("NAMESPACE") == true {
            namespaces = try? await namespace()
        }
        if let caps = await client.capabilities {
            specialUseMailboxes = await discoverSpecialUseMailboxes(capabilities: caps)
        }
    }

    private func discoverSpecialUseMailboxes(capabilities: ImapCapabilities) async -> [ImapMailbox] {
        if capabilities.supports("SPECIAL-USE") {
            if isProtonSpecialUseQuirk(capabilities) {
                if let list = try? await list(reference: "", mailbox: "%%") {
                    return list.filter { $0.specialUse != nil }
                }
                if let list = try? await list(reference: "", mailbox: "*") {
                    return list.filter { $0.specialUse != nil }
                }
                return []
            }

            if let list = try? await listSpecialUse(reference: "", mailbox: "*") {
                return list.filter { $0.specialUse != nil }
            }
            if let list = try? await list(reference: "", mailbox: "*") {
                return list.filter { $0.specialUse != nil }
            }
            return []
        }

        if capabilities.supports("XLIST"),
           let list = try? await xlist(reference: "", mailbox: "*") {
            return list.filter { $0.specialUse != nil }
        }

        return []
    }

    private nonisolated func isProtonSpecialUseQuirk(_ capabilities: ImapCapabilities) -> Bool {
        // MailKit identifies Proton quirks via XSTOP and avoids LIST (SPECIAL-USE) on those servers.
        capabilities.supports("XSTOP")
    }

    public func enable(_ capabilities: [String], maxEmptyReads: Int = 10) async throws -> [String] {
        try await ensureAuthenticatedOnly()
        return try await withSessionTimeout {
            let command = try await self.client.send(.enable(capabilities))
            var enabled: [String] = []
            var sawEnabledResponse = false
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
                        sawEnabledResponse = true
                        enabled.append(contentsOf: response.capabilities)
                    }
                    if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                        guard response.isOk else {
                            throw SessionError.imapError(status: response.status, text: response.text)
                        }

                        // iCloud quirk: some servers return tagged OK for `ENABLE QRESYNC CONDSTORE`
                        // without sending an untagged ENABLED response.
                        if !sawEnabledResponse {
                            let requested = Set(capabilities.map { $0.uppercased() })
                            if requested.contains("QRESYNC"), requested.contains("CONDSTORE") {
                                await self.client.markEnabledCapabilities(["QRESYNC", "CONDSTORE"])
                                if !enabled.contains(where: { $0.caseInsensitiveCompare("QRESYNC") == .orderedSame }) {
                                    enabled.append("QRESYNC")
                                }
                                if !enabled.contains(where: { $0.caseInsensitiveCompare("CONDSTORE") == .orderedSame }) {
                                    enabled.append("CONDSTORE")
                                }
                            }
                        }
                        return enabled
                    }
                }
            }
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        try await ensureAuthenticated()
        return try await withSessionTimeout {
            let command = try await self.client.send(.select(mailbox))
            var emptyReads = 0
            var nextState = ImapSelectedState()

            while true {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    if await self.client.isDisconnected {
                        throw SessionError.connectionClosed(message: "Connection closed by server.")
                    }
                    emptyReads += 1
                    if emptyReads > 10 {
                        try await self.throwTimeoutOrConnectionClosed()
                    }
                    continue
                }
                emptyReads = 0
                for message in messages {
                    await self.applySelectedState(&nextState, mailbox: mailbox, from: message)
                    if let response = message.response {
                        if case let .tagged(tag) = response.kind {
                            if tag == command.tag {
                                guard response.isOk else {
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
        self.pendingIdleEvents = []
        self.pendingQresyncEvents = []
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
            try await self.throwTimeoutOrConnectionClosed()
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
        self.pendingIdleEvents = []
        self.pendingQresyncEvents = []
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
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
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    public func capabilities() async -> ImapCapabilities? {
        await client.capabilities
    }

    /// Executes a single command and automatically joins the current in-flight pipeline
    /// when the command is pipeline-safe.
    ///
    /// If no compatible pipeline is active, this starts one.
    /// Untagged responses are routed to the oldest pending command in that pipeline.
    ///
    /// - Important: Commands that require interactive continuations (for example
    ///   `IDLE` and `AUTHENTICATE`) are rejected.
    /// - Important: The caller is responsible for choosing command mixes that the
    ///   target server supports for pipelining.
    public func execute(_ kind: ImapCommandKind, maxEmptyReads: Int = 10) async throws -> ImapPipelineResult {
        try await ensureIdleNotActive()
        try validatePipelineCommand(kind)
        return try await withPipelinedCommand {
            try await self.enqueueAutoPipelineCommand(kind, maxEmptyReads: maxEmptyReads)
        }
    }

    /// Waits until the currently active auto-pipelined command set has drained.
    ///
    /// This is useful when callers issue multiple concurrent `execute(...)` calls
    /// and need a synchronization point before issuing non-pipeline work.
    ///
    /// - Throws: ``SessionError/timeout`` or ``SessionError/connectionClosed(message:)``
    ///   if the wait exceeds the session timeout or the connection closes.
    public func waitForPipelineDrained() async throws {
        try await withTimeout(milliseconds: timeoutMilliseconds) {
            try await self.withCommandAccess(mode: .exclusive) {}
        }
    }

    /// Sends multiple commands without waiting between writes, then routes responses per command tag.
    ///
    /// The returned array preserves command send order.
    /// Untagged responses are routed to the oldest command that is still pending.
    ///
    /// - Important: Avoid commands that require explicit continuation handshakes (for example `IDLE`/`DONE`).
    /// - Important: The caller is responsible for choosing command mixes that the
    ///   target server supports for pipelining.
    public func pipeline(_ kinds: [ImapCommandKind], maxEmptyReads: Int = 10) async throws -> [ImapPipelineResult] {
        try await ensureIdleNotActive()
        guard !kinds.isEmpty else { return [] }

        return try await withSessionTimeout {
            var tagsInOrder: [String] = []
            var pendingTags: Set<String> = []
            var messagesByTag: [String: [ImapLiteralMessage]] = [:]
            var responseByTag: [String: ImapResponse] = [:]

            for kind in kinds {
                try self.validatePipelineCommand(kind)
                let command = try await self.client.send(kind)
                tagsInOrder.append(command.tag)
                pendingTags.insert(command.tag)
                messagesByTag[command.tag] = []
            }

            var emptyReads = 0
            while !pendingTags.isEmpty && emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    try await self.throwConnectionClosedIfDisconnected()
                    emptyReads += 1
                    continue
                }
                emptyReads = 0

                for message in messages {
                    _ = await self.ingestSelectedState(from: message)

                    if let response = message.response,
                       case let .tagged(tag) = response.kind,
                       pendingTags.contains(tag) {
                        messagesByTag[tag, default: []].append(message)
                        responseByTag[tag] = response
                        pendingTags.remove(tag)
                        continue
                    }

                    if let ownerTag = tagsInOrder.first(where: { pendingTags.contains($0) }) {
                        messagesByTag[ownerTag, default: []].append(message)
                    }
                }
            }

            if !pendingTags.isEmpty {
                try await self.throwTimeoutOrConnectionClosed()
            }

            var results: [ImapPipelineResult] = []
            results.reserveCapacity(tagsInOrder.count)
            for tag in tagsInOrder {
                guard let response = responseByTag[tag] else {
                    throw SessionError.timeout
                }
                results.append(ImapPipelineResult(
                    tag: tag,
                    response: response,
                    messages: messagesByTag[tag] ?? []
                ))
            }
            return results
        }
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
                    _ = await self.ingestSelectedState(from: message)
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

            try await self.throwTimeoutOrConnectionClosed()
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
        try ImapSort.validateCapabilities(orderBy: orderBy, capabilities: await client.capabilities)
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
                    _ = await self.ingestSelectedState(from: message)
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    _ = await self.ingestSelectedState(from: message)
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

            try await self.throwTimeoutOrConnectionClosed()
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
        try ImapSort.validateCapabilities(orderBy: orderBy, capabilities: await client.capabilities)
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
                    _ = await self.ingestSelectedState(from: message)
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    public func id(_ parameters: [String: String?]? = nil, maxEmptyReads: Int = 10) async throws -> ImapIdResponse? {
        try await ensureIdleNotActive()
        return try await withSessionTimeout {
            let command = try await self.client.send(.id(ImapId.buildArguments(parameters)))
            var emptyReads = 0
            var response: ImapIdResponse?

            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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

            try await self.throwTimeoutOrConnectionClosed()
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
        try await ensureIdleNotActive()
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        let initialCapabilitiesVersion = await client.capabilitiesVersion
        return try await withSessionTimeout {
            let command = try await self.client.send(.starttls)
            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    try await self.throwConnectionClosedIfDisconnected()
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
                        if await self.client.capabilitiesVersion == initialCapabilitiesVersion {
                            _ = try await self.client.capability()
                        }
                        return response
                    }
                }
            }
            try await self.throwTimeoutOrConnectionClosed()
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
                    try await self.throwConnectionClosedIfDisconnected()
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
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    public func readIdleEvents(maxEmptyReads: Int = 10) async throws -> [ImapIdleEvent] {
        try await ensureSelected(allowIdle: true)
        return try await withSessionTimeout {
            var events = await self.dequeuePendingIdleEvents(limit: Int.max)
            if !events.isEmpty {
                return events
            }

            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    try await self.throwConnectionClosedIfDisconnected()
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message)
                }
                events.append(contentsOf: await self.dequeuePendingIdleEvents(limit: Int.max))
                if !events.isEmpty {
                    return events
                }
            }
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    public func stopIdle() async throws {
        try await ensureSelected(allowIdle: true)
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
                    try await self.throwConnectionClosedIfDisconnected()
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
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    private func setIdleTag(_ tag: String?) {
        idleTag = tag
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxEmptyReads: Int = 10) async throws -> [ImapQresyncEvent] {
        try await ensureSelected(allowIdle: true)
        return try await withSessionTimeout {
            var events = await self.dequeuePendingQresyncEvents(limit: Int.max)
            if !events.isEmpty {
                return events
            }

            var emptyReads = 0
            while emptyReads < maxEmptyReads {
                try Task.checkCancellation()
                let messages = await self.client.nextMessages()
                if messages.isEmpty {
                    try await self.throwConnectionClosedIfDisconnected()
                    emptyReads += 1
                    continue
                }
                emptyReads = 0
                for message in messages {
                    _ = await self.ingestSelectedState(from: message, validity: validity)
                }
                events.append(contentsOf: await self.dequeuePendingQresyncEvents(limit: Int.max))
                if !events.isEmpty {
                    return events
                }
            }
            try await self.throwTimeoutOrConnectionClosed()
        }
    }

    private func enqueueAutoPipelineCommand(_ kind: ImapCommandKind, maxEmptyReads: Int) async throws -> ImapPipelineResult {
        try await withCheckedThrowingContinuation { continuation in
            let requestID = UUID()
            autoPipelineOrder.append(requestID)
            autoPipelineRequests[requestID] = AutoPipelineRequest(
                id: requestID,
                kind: kind,
                maxEmptyReads: max(1, maxEmptyReads),
                continuation: continuation,
                tag: nil,
                messages: []
            )
            ensureAutoPipelineDriverRunning()
        }
    }

    private func ensureAutoPipelineDriverRunning() {
        guard autoPipelineDriverTask == nil else { return }
        autoPipelineDriverTask = Task {
            await self.runAutoPipelineDriver()
        }
    }

    private func runAutoPipelineDriver() async {
        defer { autoPipelineDriverTask = nil }
        do {
            try await driveAutoPipeline()
        } catch {
            failAllAutoPipelineRequests(with: error)
        }
    }

    private func driveAutoPipeline() async throws {
        var emptyReads = 0

        while !autoPipelineOrder.isEmpty {
            try await sendAutoPipelineCommands()
            guard !autoPipelineOrder.isEmpty else { break }

            let messages = await client.nextMessages()
            if messages.isEmpty {
                try await throwConnectionClosedIfDisconnected()
                emptyReads += 1
                if emptyReads >= autoPipelineReadLimit() {
                    throw SessionError.timeout
                }
                continue
            }

            emptyReads = 0
            for message in messages {
                _ = await ingestSelectedState(from: message)

                if let response = message.response,
                   case let .tagged(tag) = response.kind,
                   let requestID = autoPipelineTagMap[tag] {
                    appendAutoPipelineMessage(message, requestID: requestID)
                    completeAutoPipelineRequest(requestID: requestID, response: response)
                    continue
                }

                if let requestID = autoPipelineOrder.first {
                    appendAutoPipelineMessage(message, requestID: requestID)
                }
            }
        }
    }

    private func sendAutoPipelineCommands() async throws {
        for requestID in autoPipelineOrder {
            guard var request = autoPipelineRequests[requestID], request.tag == nil else { continue }
            let command = try await client.send(request.kind)
            request.tag = command.tag
            autoPipelineRequests[requestID] = request
            autoPipelineTagMap[command.tag] = requestID
        }
    }

    private func appendAutoPipelineMessage(_ message: ImapLiteralMessage, requestID: UUID) {
        guard var request = autoPipelineRequests[requestID] else { return }
        request.messages.append(message)
        autoPipelineRequests[requestID] = request
    }

    private func completeAutoPipelineRequest(requestID: UUID, response: ImapResponse) {
        guard let request = autoPipelineRequests.removeValue(forKey: requestID) else { return }
        if let index = autoPipelineOrder.firstIndex(of: requestID) {
            autoPipelineOrder.remove(at: index)
        }
        if let tag = request.tag {
            autoPipelineTagMap.removeValue(forKey: tag)
        }
        request.continuation.resume(returning: ImapPipelineResult(
            tag: request.tag ?? "",
            response: response,
            messages: request.messages
        ))
    }

    private func failAllAutoPipelineRequests(with error: Error) {
        let pending = Array(autoPipelineRequests.values)
        autoPipelineRequests.removeAll()
        autoPipelineOrder.removeAll()
        autoPipelineTagMap.removeAll()
        for request in pending {
            request.continuation.resume(throwing: error)
        }
    }

    private func autoPipelineReadLimit() -> Int {
        autoPipelineRequests.values.map(\.maxEmptyReads).max() ?? 10
    }

    private func ensureAuthenticated(allowIdle: Bool = false) async throws {
        let current = ImapSessionState(await client.state)
        guard current == .authenticated || current == .selected else {
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        }
        if !allowIdle {
            try await ensureIdleNotActive()
        }
    }

    private func ensureAuthenticatedOnly(allowIdle: Bool = false) async throws {
        let current = ImapSessionState(await client.state)
        guard current == .authenticated else {
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        }
        if !allowIdle {
            try await ensureIdleNotActive()
        }
    }

    private func ensureSelected(allowIdle: Bool = false) async throws {
        let current = ImapSessionState(await client.state)
        guard current == .selected else {
            throw SessionError.invalidImapState(expected: .selected, actual: current)
        }
        if !allowIdle {
            try await ensureIdleNotActive()
        }
    }

    private func ensureIdleNotActive() async throws {
        if idleTag != nil {
            throw SessionError.imapError(status: .bad, text: "IDLE command is active.")
        }
    }

    nonisolated private func validatePipelineCommand(_ kind: ImapCommandKind) throws {
        switch kind {
        case .idle, .authenticate:
            throw SessionError.imapError(status: .bad, text: "Command is not pipeline-safe.")
        default:
            return
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
            if shouldBufferIdleEvent(idle, line: message.line) {
                pendingIdleEvents.append(idle)
            }
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
            pendingQresyncEvents.append(event)
            return event
        }
        return nil
    }

    private func dequeuePendingIdleEvents(limit: Int) -> [ImapIdleEvent] {
        guard limit > 0, !pendingIdleEvents.isEmpty else { return [] }
        let count = min(limit, pendingIdleEvents.count)
        let events = Array(pendingIdleEvents.prefix(count))
        pendingIdleEvents.removeFirst(count)
        return events
    }

    private func dequeuePendingQresyncEvents(limit: Int) -> [ImapQresyncEvent] {
        guard limit > 0, !pendingQresyncEvents.isEmpty else { return [] }
        let count = min(limit, pendingQresyncEvents.count)
        let events = Array(pendingQresyncEvents.prefix(count))
        pendingQresyncEvents.removeFirst(count)
        return events
    }

    private func shouldBufferIdleEvent(_ event: ImapIdleEvent, line: String) -> Bool {
        switch event {
        case .other:
            return isSelectedStateUntaggedFetch(line)
        default:
            return true
        }
    }

    private nonisolated func isSelectedStateUntaggedFetch(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") else { return false }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, Int(parts[1]) != nil else { return false }
        return parts[2].uppercased() == "FETCH"
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

    private nonisolated func validateGreeting(_ greeting: ImapResponse?) throws -> ImapResponse {
        guard let greeting else {
            throw SessionError.timeout
        }
        if greeting.status == .ok || greeting.status == .preauth {
            return greeting
        }
        throw SessionError.imapError(status: greeting.status, text: greeting.text)
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
