//
// AsyncSmtpClient.swift
//
// Async SMTP client backed by AsyncTransport.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpClient {
    private let transport: AsyncTransport
    private let queue = AsyncQueue<[UInt8]>()
    private var readerTask: Task<Void, Never>?
    private var decoder = SmtpResponseDecoder()

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: SmtpCapabilities?
    public private(set) var isAuthenticated: Bool = false
    public var protocolLogger: ProtocolLoggerType

    public init(transport: AsyncTransport, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.transport = transport
        self.protocolLogger = protocolLogger
    }

    public func start() async throws {
        try await transport.start()
        state = .connected
        isAuthenticated = false
        readerTask = Task {
            for await chunk in transport.incoming {
                await queue.enqueue(chunk)
            }
            await queue.finish()
        }
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.stop()
        await queue.finish()
        state = .disconnected
        isAuthenticated = false
    }

    public func beginAuthentication() {
        guard state == .connected else { return }
        state = .authenticating
        isAuthenticated = false
    }

    public func endAuthentication() {
        if state == .authenticating {
            state = .connected
        }
    }

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

    public func makeCommand(_ kind: SmtpCommandKind) -> SmtpCommand {
        kind.command()
    }

    @discardableResult
    public func send(_ kind: SmtpCommandKind) async throws -> [UInt8] {
        if case .auth = kind {
            beginAuthentication()
        }
        let command = makeCommand(kind)
        return try await send(command)
    }

    @discardableResult
    public func send(_ command: SmtpCommand) async throws -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

    @discardableResult
    public func sendRaw(_ bytes: [UInt8]) async throws -> [UInt8] {
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        try await transport.send(bytes)
        return bytes
    }

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

    public func nextResponses() async -> [SmtpResponse] {
        guard let chunk = await queue.dequeue() else {
            return []
        }
        protocolLogger.logServer(chunk, offset: 0, count: chunk.count)
        let responses = decoder.append(chunk)
        for response in responses where state == .authenticating {
            handleAuthenticationResponse(response)
        }
        return responses
    }

    public func waitForResponse() async -> SmtpResponse? {
        while true {
            let responses = await nextResponses()
            if let first = responses.first {
                return first
            }
            if responses.isEmpty {
                return nil
            }
        }
    }

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
