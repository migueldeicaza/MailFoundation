//
// AsyncSmtpClient.swift
//
// Async SMTP client backed by AsyncTransport.
//

/// A low-level asynchronous SMTP client for sending commands and receiving responses.
///
/// `AsyncSmtpClient` provides direct access to the SMTP protocol using Swift concurrency.
/// It is implemented as an actor to ensure thread-safe access to the connection state.
/// For most use cases, consider using ``AsyncSmtpTransport`` which provides a higher-level
/// API with automatic handling of common operations.
///
/// ## Basic Usage
///
/// ```swift
/// let transport = try NetworkTransport(host: "smtp.example.com", port: 587)
/// let client = AsyncSmtpClient(transport: transport)
///
/// try await client.start()
///
/// // Read the greeting
/// let greeting = await client.waitForResponse()
///
/// // Send EHLO and get capabilities
/// let capabilities = try await client.ehlo(domain: "client.example.com")
///
/// // Authenticate if needed
/// if capabilities?.supports("AUTH") == true {
///     let response = try await client.authenticate(mechanism: "PLAIN", initialResponse: encodedCredentials)
/// }
///
/// // Send a message...
///
/// await client.stop()
/// ```
///
/// ## Protocol Logging
///
/// You can capture the SMTP conversation for debugging by providing a protocol logger:
///
/// ```swift
/// let logger = StreamProtocolLogger(stream: FileHandle.standardError)
/// let client = AsyncSmtpClient(transport: transport, protocolLogger: logger)
/// ```
///
/// ## See Also
/// - ``AsyncSmtpTransport``
/// - ``SmtpClient``
/// - ``SmtpCommand``
/// - ``SmtpResponse``
@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpClient {
    /// The underlying async transport for network I/O.
    private let transport: AsyncTransport

    /// Queue for buffering incoming data chunks.
    private let queue = AsyncQueue<[UInt8]>()

    /// Background task that reads from the transport and queues data.
    private var readerTask: Task<Void, Never>?

    /// Decodes incoming bytes into SMTP responses.
    private var decoder = SmtpResponseDecoder()

    /// Represents the connection and authentication state of the SMTP client.
    public enum State: Sendable {
        /// The client is not connected to any server.
        case disconnected

        /// The client is connected but not authenticated.
        case connected

        /// The client is in the process of authenticating.
        case authenticating
    }

    /// The current state of the client.
    ///
    /// This reflects the connection and authentication status.
    public private(set) var state: State = .disconnected

    /// The server capabilities discovered during EHLO.
    ///
    /// This is populated after calling ``ehlo(domain:)``. Use this to check
    /// for supported extensions before using them.
    public private(set) var capabilities: SmtpCapabilities?

    /// Whether the client has successfully authenticated.
    ///
    /// This is set to `true` after a successful authentication response.
    public private(set) var isAuthenticated: Bool = false

    /// The protocol logger for recording the SMTP conversation.
    ///
    /// Set this to capture the protocol exchange for debugging.
    public var protocolLogger: ProtocolLoggerType

    /// Creates a new async SMTP client.
    ///
    /// - Parameters:
    ///   - transport: The async transport to use for network I/O.
    ///   - protocolLogger: The logger for recording protocol exchanges.
    ///     Defaults to ``NullProtocolLogger`` which discards all output.
    public init(transport: AsyncTransport, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.transport = transport
        self.protocolLogger = protocolLogger
    }

    /// Starts the client and connects to the server.
    ///
    /// This starts the underlying transport and begins reading data in the background.
    /// After calling this, you should wait for the server greeting using ``waitForResponse()``.
    ///
    /// - Throws: An error if the transport fails to start.
    public func start() async throws {
        try await transport.start()
        state = .connected
        isAuthenticated = false
        readerTask = Task {
            for await chunk in transport.incoming {
                await queue.enqueue(chunk)
            }
            await queue.finish()
            await self.setDisconnected()
        }
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
        isAuthenticated = false
    }

    /// Begins an authentication sequence.
    ///
    /// Call this before sending an AUTH command to update the client state.
    /// The ``authenticate(mechanism:initialResponse:)`` method calls this automatically.
    public func beginAuthentication() {
        guard state == .connected else { return }
        state = .authenticating
        isAuthenticated = false
    }

    /// Ends an authentication sequence.
    ///
    /// Call this after authentication completes (successfully or not) to
    /// restore normal state.
    public func endAuthentication() {
        if state == .authenticating {
            state = .connected
        }
    }

    /// Handles an authentication response from the server.
    ///
    /// Updates the client state based on the response code. A 2xx response
    /// indicates successful authentication; a 4xx or 5xx response indicates failure.
    ///
    /// - Parameter response: The server response to an AUTH command.
    public func handleAuthenticationResponse(_ response: SmtpResponse) {
        guard state == .authenticating else { return }
        if response.code >= 200 && response.code < 300 {
            state = .connected
            isAuthenticated = true
        } else if response.code >= 400 {
            state = .connected
            isAuthenticated = false
        }
    }

    /// Creates an SMTP command from a command kind.
    ///
    /// - Parameter kind: The type of command to create.
    /// - Returns: A new ``SmtpCommand`` instance.
    public func makeCommand(_ kind: SmtpCommandKind) -> SmtpCommand {
        kind.command()
    }

    /// Sends an SMTP command by kind.
    ///
    /// If the command is an AUTH command, this automatically calls
    /// ``beginAuthentication()`` first.
    ///
    /// - Parameter kind: The type of command to send.
    /// - Returns: The bytes that were sent.
    /// - Throws: An error if sending fails.
    @discardableResult
    public func send(_ kind: SmtpCommandKind) async throws -> [UInt8] {
        if case .auth = kind {
            beginAuthentication()
        }
        let command = makeCommand(kind)
        return try await send(command)
    }

    /// Sends an SMTP command.
    ///
    /// The command is serialized and sent to the server.
    ///
    /// - Parameter command: The command to send.
    /// - Returns: The bytes that were sent.
    /// - Throws: An error if sending fails.
    @discardableResult
    public func send(_ command: SmtpCommand) async throws -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

    /// Sends raw bytes to the server.
    ///
    /// Use this for sending data that is not a standard SMTP command,
    /// such as authentication challenges or message content.
    ///
    /// - Parameter bytes: The bytes to send.
    /// - Returns: The bytes that were sent.
    /// - Throws: An error if sending fails.
    @discardableResult
    public func sendRaw(_ bytes: [UInt8]) async throws -> [UInt8] {
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

    /// Sends a line of text to the server.
    ///
    /// Automatically appends CRLF if not already present.
    ///
    /// - Parameter line: The line to send.
    /// - Returns: The bytes that were sent.
    /// - Throws: An error if sending fails.
    @discardableResult
    public func sendLine(_ line: String) async throws -> [UInt8] {
        let serialized: String
        if line.hasSuffix("\r\n") {
            serialized = line
        } else {
            serialized = "\(line)\r\n"
        }
        let bytes = Array(serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

    /// Reads and decodes the next batch of responses.
    ///
    /// Waits for data to arrive from the server and decodes it into responses.
    ///
    /// - Returns: The decoded responses, or `nil` if the connection is closed.
    public func nextResponses() async -> [SmtpResponse]? {
        guard let chunk = await queue.dequeue() else {
            return nil
        }
        protocolLogger.logServer(chunk, offset: 0, count: chunk.count)
        let responses = decoder.append(chunk)
        for response in responses where state == .authenticating {
            handleAuthenticationResponse(response)
        }
        return responses
    }

    /// Waits for a complete response from the server.
    ///
    /// Keeps reading until a complete response is received or the connection closes.
    ///
    /// - Returns: The first complete response, or `nil` if the connection closed.
    public func waitForResponse() async -> SmtpResponse? {
        while let responses = await nextResponses() {
            if let first = responses.first {
                return first
            }
        }
        return nil
    }

    /// Sends message data using the DATA command.
    ///
    /// This sends the DATA command, waits for the 354 intermediate response,
    /// then sends the message content with proper dot-stuffing and termination.
    ///
    /// - Parameter message: The message content to send.
    /// - Returns: The final server response, or `nil` if the connection closed.
    /// - Throws: An error if sending fails.
    public func sendData(_ message: [UInt8]) async throws -> SmtpResponse? {
        let command = makeCommand(.data)
        _ = try await send(command)
        guard let intermediate = await waitForResponse() else {
            return nil
        }
        guard intermediate.code == 354 else {
            return intermediate
        }

        let payload = SmtpDataWriter.prepare(message)
        protocolLogger.logClient(payload, offset: 0, count: payload.count)
        try await transport.send(payload)
        return await waitForResponse()
    }

    /// Sends an EHLO command and parses the capabilities.
    ///
    /// This is a convenience method that sends EHLO, waits for the response,
    /// and parses the server capabilities.
    ///
    /// - Parameter domain: The client's domain name or IP address.
    /// - Returns: The parsed capabilities, or `nil` if the command failed.
    /// - Throws: An error if sending fails.
    public func ehlo(domain: String) async throws -> SmtpCapabilities? {
        let command = makeCommand(.ehlo(domain))
        _ = try await send(command)
        guard let response = await waitForResponse() else {
            return nil
        }
        let parsed = SmtpCapabilities.parseEhlo(response)
        capabilities = parsed
        return parsed
    }

    /// Authenticates with the server using a SASL mechanism.
    ///
    /// This sends the AUTH command and handles the response to update
    /// the authentication state.
    ///
    /// - Parameters:
    ///   - mechanism: The SASL mechanism name (e.g., "PLAIN", "LOGIN", "XOAUTH2").
    ///   - initialResponse: Optional initial response data (base64-encoded).
    /// - Returns: The server response, or `nil` if the connection closed.
    /// - Throws: An error if sending fails.
    public func authenticate(mechanism: String, initialResponse: String? = nil) async throws -> SmtpResponse? {
        beginAuthentication()
        let command = makeCommand(.auth(mechanism, initialResponse: initialResponse))
        _ = try await send(command)
        let response = await waitForResponse()
        if let response {
            handleAuthenticationResponse(response)
        }
        return response
    }
}
