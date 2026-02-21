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
// ImapClient.swift
//
// Minimal scaffolding for IMAP client.
//

import Foundation

/// A low-level IMAP client for sending commands and receiving responses.
///
/// `ImapClient` provides a low-level interface for IMAP protocol communication.
/// For most use cases, prefer ``ImapMailStore`` or ``AsyncImapMailStore`` which
/// provide a higher-level, more convenient API.
///
/// ## Overview
///
/// This class handles:
/// - Command tag generation
/// - Response parsing
/// - State tracking (connected, authenticated, selected)
/// - Protocol logging
/// - Literal handling
///
/// ## Usage Example
///
/// ```swift
/// let client = ImapClient(protocolLogger: ConsoleProtocolLogger())
///
/// // Connect via transport
/// let transport = try TransportFactory.make(host: "imap.example.com", port: 993, backend: .ssl)
/// client.connect(transport: transport)
///
/// // Send commands manually
/// let loginCmd = client.send(.login(user: "user", password: "pass"))
/// let response = client.waitForTagged(loginCmd.tag)
///
/// // Higher-level execute
/// if let response = client.execute(.select(mailbox: "INBOX")) {
///     print("Selected INBOX")
/// }
/// ```
///
/// ## State Machine
///
/// The client tracks connection state:
/// - `disconnected` - Not connected
/// - `connected` - Connected but not authenticated
/// - `authenticating` - Authentication in progress
/// - `authenticated` - Logged in, no folder selected
/// - `selected` - A folder is currently selected
///
/// ## See Also
///
/// - ``ImapMailStore``
/// - ``ImapSession``
/// - ``ImapCommand``
public final class ImapClient {
    private enum PendingCommand {
        case login
        case authenticate
        case select
        case examine
        case close
        case logout
    }

    private let detector = ImapAuthenticationSecretDetector()
    private var tagGenerator = ImapTagGenerator()
    private var decoder = ImapResponseDecoder()
    private var literalDecoder = ImapLiteralDecoder()
    private var transport: Transport?
    private var pending: [String: PendingCommand] = [:]
    private let emptyReadDelaySeconds: TimeInterval = 0.05

    /// The connection state of the IMAP client.
    public enum State: Sendable {
        /// Not connected to any server.
        case disconnected

        /// Connected but not authenticated.
        case connected

        /// Authentication is in progress.
        case authenticating

        /// Authenticated but no folder selected.
        case authenticated

        /// A folder is currently selected.
        case selected
    }

    /// The current state of the client.
    public private(set) var state: State = .disconnected

    /// The capabilities advertised by the server.
    ///
    /// This is populated after connecting and may be updated after authentication.
    public private(set) var capabilities: ImapCapabilities?
    public private(set) var capabilitiesVersion: Int = 0

    /// Whether the last write operation succeeded.
    public private(set) var lastWriteSucceeded: Bool = true

    /// The protocol logger for debugging IMAP communication.
    public var protocolLogger: ProtocolLoggerType {
        didSet {
            protocolLogger.authenticationSecretDetector = detector
        }
    }

    /// Whether the client is currently connected.
    public private(set) var isConnected: Bool = false

    /// Creates a new IMAP client.
    ///
    /// - Parameter protocolLogger: The logger for protocol-level debugging.
    public init(protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.protocolLogger = protocolLogger
        self.protocolLogger.authenticationSecretDetector = detector
    }

    /// Logs a connection to the specified URI.
    ///
    /// This method only updates state and logs; it does not establish a network connection.
    /// Use `connect(transport:)` to connect with a transport.
    ///
    /// - Parameter uri: The URI being connected to.
    public func connect(to uri: URL) {
        protocolLogger.logConnect(uri)
        isConnected = true
        state = .connected
    }

    /// Connects using the specified transport.
    ///
    /// - Parameter transport: The transport to use for communication.
    public func connect(transport: Transport) {
        self.transport = transport
        transport.open()
        isConnected = true
        state = .connected
    }

    /// Disconnects from the server.
    public func disconnect() {
        isConnected = false
        state = .disconnected
    }

    /// Begins the authentication phase.
    ///
    /// This enables credential masking in protocol logs.
    public func beginAuthentication() {
        guard isConnected else { return }
        detector.isAuthenticating = true
        state = .authenticating
    }

    /// Ends the authentication phase.
    public func endAuthentication() {
        detector.isAuthenticating = false
        state = isConnected ? .authenticated : .disconnected
    }

    /// Creates a command with the specified name and arguments.
    ///
    /// - Parameters:
    ///   - name: The command name (e.g., "SELECT", "FETCH").
    ///   - arguments: The command arguments.
    /// - Returns: The command with a unique tag.
    public func makeCommand(_ name: String, arguments: String? = nil) -> ImapCommand {
        let tag = tagGenerator.nextTag()
        return ImapCommand(tag: tag, name: name, arguments: arguments)
    }

    /// Creates a command from a command kind.
    ///
    /// - Parameter kind: The command kind.
    /// - Returns: The command with a unique tag.
    public func makeCommand(_ kind: ImapCommandKind) -> ImapCommand {
        let tag = tagGenerator.nextTag()
        return kind.command(tag: tag)
    }

    /// Sends a command and returns it.
    ///
    /// The command is serialized and written to the transport. State is updated
    /// automatically for commands that affect it (LOGIN, SELECT, etc.).
    ///
    /// - Parameter kind: The command kind to send.
    /// - Returns: The sent command.
    @discardableResult
    public func send(_ kind: ImapCommandKind) -> ImapCommand {
        let command = makeCommand(kind)
        if case .login = kind {
            beginAuthentication()
            pending[command.tag] = .login
        } else if case .authenticate = kind {
            beginAuthentication()
            pending[command.tag] = .authenticate
        } else if case .select = kind {
            pending[command.tag] = .select
        } else if case .examine = kind {
            pending[command.tag] = .examine
        } else if case .close = kind {
            pending[command.tag] = .close
        } else if case .logout = kind {
            pending[command.tag] = .logout
        }
        _ = send(command)
        return command
    }

    /// Sends a command directly.
    ///
    /// - Parameter command: The command to send.
    /// - Returns: The serialized command bytes.
    @discardableResult
    public func send(_ command: ImapCommand) -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        let written = transport?.write(bytes) ?? 0
        lastWriteSucceeded = written == bytes.count
        return bytes
    }

    /// Sends raw bytes directly.
    ///
    /// - Parameter bytes: The raw bytes to send.
    public func sendLiteral(_ bytes: [UInt8]) {
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        let written = transport?.write(bytes) ?? 0
        lastWriteSucceeded = written == bytes.count
    }

    /// Processes incoming data and returns parsed responses.
    ///
    /// - Parameter bytes: The incoming data.
    /// - Returns: The parsed responses.
    public func handleIncoming(_ bytes: [UInt8]) -> [ImapResponse] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let responses = decoder.append(bytes)
        handleResponses(responses)
        return responses
    }

    /// Processes incoming data with literal support.
    ///
    /// - Parameter bytes: The incoming data.
    /// - Returns: The parsed messages with literal data.
    public func handleIncomingWithLiterals(_ bytes: [UInt8]) -> [ImapLiteralMessage] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let messages = literalDecoder.append(bytes)
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

    /// Processes multiple responses.
    ///
    /// - Parameter responses: The responses to process.
    public func handleResponses(_ responses: [ImapResponse]) {
        for response in responses {
            handleResponse(response)
        }
    }

    /// Processes a single response and updates state accordingly.
    ///
    /// - Parameter response: The response to process.
    public func handleResponse(_ response: ImapResponse) {
        if case .untagged = response.kind {
            if response.status == .preauth {
                state = .authenticated
            } else if response.status == .bye {
                state = .disconnected
                isConnected = false
            }
            return
        }

        if case let .tagged(tag) = response.kind {
            guard let pending = pending.removeValue(forKey: tag) else { return }
            switch pending {
            case .login, .authenticate:
                if response.status == .ok {
                    state = .authenticated
                } else {
                    state = .connected
                }
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
                    isConnected = false
                }
            }
        }
    }

    /// Reads and processes available data from the transport.
    ///
    /// - Returns: The parsed responses.
    public func receive() -> [ImapResponse] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else {
            Thread.sleep(forTimeInterval: emptyReadDelaySeconds)
            return []
        }
        return handleIncoming(bytes)
    }

    /// Reads and processes available data with literal support.
    ///
    /// - Returns: The parsed messages with literal data.
    public func receiveWithLiterals() -> [ImapLiteralMessage] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else {
            Thread.sleep(forTimeInterval: emptyReadDelaySeconds)
            return []
        }
        return handleIncomingWithLiterals(bytes)
    }

    /// Waits for a tagged response with the specified tag.
    ///
    /// - Parameters:
    ///   - tag: The command tag to wait for.
    ///   - maxReads: Maximum number of read attempts.
    /// - Returns: The tagged response, or `nil` if not received within maxReads attempts.
    public func waitForTagged(_ tag: String, maxReads: Int = 2400) -> ImapResponse? {
        var reads = 0
        while reads < maxReads {
            let messages = receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response, case let .tagged(found) = response.kind, found == tag {
                    return response
                }
            }
        }
        return nil
    }

    /// Waits for a continuation response.
    ///
    /// Continuation responses ("+") indicate the server is ready for more data,
    /// such as during literal uploads or SASL authentication.
    ///
    /// - Parameter maxReads: Maximum number of read attempts.
    /// - Returns: The continuation response, or `nil` if not received.
    public func waitForContinuation(maxReads: Int = 2400) -> ImapResponse? {
        var reads = 0
        while reads < maxReads {
            let messages = receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response, case .continuation = response.kind {
                    return response
                }
            }
        }
        return nil
    }

    /// Sends a command and waits for its tagged response.
    ///
    /// This is a convenience method that combines `send(_:)` and `waitForTagged(_:)`.
    ///
    /// - Parameters:
    ///   - kind: The command kind to execute.
    ///   - maxReads: Maximum number of read attempts.
    /// - Returns: The tagged response, or `nil` if not received.
    public func execute(_ kind: ImapCommandKind, maxReads: Int = 2400) -> ImapResponse? {
        let command = send(kind)
        return waitForTagged(command.tag, maxReads: maxReads)
    }
}
