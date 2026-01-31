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
// AsyncImapClient.swift
//
// Async IMAP client backed by AsyncTransport.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapClient {
    private enum PendingCommand {
        case login
        case authenticate
        case select
        case examine
        case close
        case logout
    }

    private let transport: AsyncTransport
    private let queue = AsyncQueue<[UInt8]>()
    private var readerTask: Task<Void, Never>?
    private var literalDecoder = ImapLiteralDecoder()
    private var tagGenerator = ImapTagGenerator()
    private var pending: [String: PendingCommand] = [:]
    private let detector = ImapAuthenticationSecretDetector()

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
        case authenticated
        case selected
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: ImapCapabilities?
    public private(set) var capabilitiesVersion: Int = 0
    public var protocolLogger: ProtocolLoggerType {
        didSet {
            protocolLogger.authenticationSecretDetector = detector
        }
    }

    public var isDisconnected: Bool {
        state == .disconnected
    }

    /// Sets the protocol logger for debugging.
    public func setProtocolLogger(_ logger: sending ProtocolLoggerType) {
        self.protocolLogger = logger
    }

    public init(transport: AsyncTransport, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.transport = transport
        self.protocolLogger = protocolLogger
        self.protocolLogger.authenticationSecretDetector = detector
    }

    public func start() async throws {
        try await transport.start()
        state = .connected
        readerTask = Task {
            for await chunk in transport.incoming {
                await queue.enqueue(chunk)
            }
            await self.setDisconnected()
            await queue.finish()
        }
    }

    /// Starts the client with implicit TLS enabled (for IMAPS on port 993).
    ///
    /// This method configures TLS before establishing the connection, which is
    /// required for implicit TLS where encryption starts immediately.
    ///
    /// - Parameter validateCertificate: Whether to validate the server certificate.
    /// - Throws: An error if the transport does not support implicit TLS or the connection fails.
    public func startSecure(validateCertificate: Bool = true) async throws {
        func finishStart() {
            state = .connected
            readerTask = Task {
                for await chunk in transport.incoming {
                    await queue.enqueue(chunk)
                }
                await self.setDisconnected()
                await queue.finish()
            }
        }

        #if canImport(Network)
        if let networkTransport = transport as? NetworkTransport {
            try await networkTransport.startSecure(validateCertificate: validateCertificate)
            finishStart()
            return
        }
        #endif

        #if !os(iOS)
        if let socketTransport = transport as? SocketTransport {
            try await socketTransport.startSecure(validateCertificate: validateCertificate)
            finishStart()
            return
        }
        #endif

        #if canImport(COpenSSL)
        if let openSSLTransport = transport as? OpenSSLTransport {
            try await openSSLTransport.startSecure(validateCertificate: validateCertificate)
            finishStart()
            return
        }
        #endif

        throw AsyncTransportError.connectionFailed
    }

    private func setDisconnected() {
        state = .disconnected
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.stop()
        await queue.finish()
        state = .disconnected
    }

    public func makeCommand(_ kind: ImapCommandKind) -> ImapCommand {
        let tag = tagGenerator.nextTag()
        return kind.command(tag: tag)
    }

    @discardableResult
    public func send(_ kind: ImapCommandKind) async throws -> ImapCommand {
        let command = makeCommand(kind)
        switch kind {
        case .login:
            state = .authenticating
            pending[command.tag] = .login
        case .authenticate:
            state = .authenticating
            pending[command.tag] = .authenticate
        case .select:
            pending[command.tag] = .select
        case .examine:
            pending[command.tag] = .examine
        case .close:
            pending[command.tag] = .close
        case .logout:
            pending[command.tag] = .logout
        default:
            break
        }
        _ = try await send(command)
        return command
    }

    @discardableResult
    public func send(_ command: ImapCommand) async throws -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

    public func sendLiteral(_ bytes: [UInt8]) async throws {
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
    }

    public func nextMessages() async -> [ImapLiteralMessage] {
        let chunk = await queue.dequeue()
        guard let chunk else {
            return []
        }
        protocolLogger.logServer(chunk, offset: 0, count: chunk.count)
        let messages = literalDecoder.append(chunk)
        for message in messages {
            if let response = message.response {
                handleResponse(response)
            }
            if let parsed = ImapCapabilities.parse(from: message.line) {
                capabilities = parsed
                capabilitiesVersion += 1
            }
        }
        return messages
    }

    public func waitForContinuation() async -> ImapResponse? {
        while true {
            let messages = await nextMessages()
            if messages.isEmpty {
                return nil
            }
            for message in messages {
                if let response = message.response, case .continuation = response.kind {
                    return response
                }
            }
        }
    }

    public func waitForTagged(_ tag: String) async -> ImapResponse? {
        while true {
            let messages = await nextMessages()
            if messages.isEmpty {
                return nil
            }
            for message in messages {
                if let response = message.response {
                    if case let .tagged(foundTag) = response.kind, foundTag == tag {
                        return response
                    }
                }
            }
        }
    }

    public func capability() async throws -> ImapResponse? {
        let command = makeCommand(.capability)
        _ = try await send(command)
        return await waitForTagged(command.tag)
    }

    public func login(user: String, password: String) async throws -> ImapResponse? {
        detector.isAuthenticating = true
        defer { detector.isAuthenticating = false }
        let command = try await send(.login(user, password))
        let response = await waitForTagged(command.tag)
        if response?.status == .ok {
            state = .authenticated
        } else if response != nil {
            state = .connected
        }
        return response
    }

    /// Authenticates using SASL mechanism
    public func authenticate(_ auth: ImapAuthentication) async throws -> ImapResponse? {
        let initialCapabilitiesVersion = capabilitiesVersion
        let supportsSaslIr = capabilities?.supports("SASL-IR") ?? false
        let initialResponse = supportsSaslIr ? auth.initialResponse : nil
        var pendingInitialResponse = supportsSaslIr ? nil : auth.initialResponse
        let command = try await send(.authenticate(auth.mechanism, initialResponse: initialResponse))
        detector.isAuthenticating = true
        defer { detector.isAuthenticating = false }

        // Handle challenge-response if needed
        if auth.responder != nil || pendingInitialResponse != nil {
            while true {
                let messages = await nextMessages()
                if messages.isEmpty {
                    return nil
                }
                for message in messages {
                    if let response = message.response {
                        // Check for tagged response (success or failure)
                        if case let .tagged(tag) = response.kind, tag == command.tag {
                            if response.status == .ok {
                                state = .authenticated
                            } else {
                                state = .connected
                            }
                            return response
                        }
                        // Check for continuation request
                        if case .continuation = response.kind {
                            let challenge = response.text ?? ""
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
                                // Empty response for final verification
                                try await sendLiteral(Array("\r\n".utf8))
                            } else {
                                try await sendLiteral(Array("\(responseData)\r\n".utf8))
                            }
                        }
                    }
                }
            }
        }

        // No responder - just wait for tagged response
        let response = await waitForTagged(command.tag)
        if response?.status == .ok {
            state = .authenticated
        } else if response != nil {
            state = .connected
        }
        if response?.status == .ok, capabilitiesVersion == initialCapabilitiesVersion {
            _ = try? await capability()
        }
        return response
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        let command = try await send(.select(mailbox))
        let response = await waitForTagged(command.tag)
        if response?.status == .ok {
            state = .selected
        }
        return response
    }

    public func close() async throws -> ImapResponse? {
        let command = try await send(.close)
        let response = await waitForTagged(command.tag)
        if response?.status == .ok {
            state = .authenticated
        }
        return response
    }

    public func logout() async throws -> ImapResponse? {
        let command = try await send(.logout)
        let response = await waitForTagged(command.tag)
        if response?.status == .ok || response?.status == .bye {
            state = .disconnected
        }
        return response
    }

    private func handleResponse(_ response: ImapResponse) {
        if case .untagged = response.kind {
            if response.status == .preauth {
                state = .authenticated
            } else if response.status == .bye {
                state = .disconnected
            }
            return
        }

        if case let .tagged(tag) = response.kind, let pending = pending.removeValue(forKey: tag) {
            switch pending {
            case .login, .authenticate:
                state = response.status == .ok ? .authenticated : .connected
            case .select, .examine:
                if response.status == .ok {
                    state = .selected
                }
            case .close:
                if response.status == .ok {
                    state = .authenticated
                }
            case .logout:
                if response.status == .ok || response.status == .bye {
                    state = .disconnected
                }
            }
            return
        }

        if state == .authenticating, response.status == .ok {
            state = .authenticated
        }
    }
}
