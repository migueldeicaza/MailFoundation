//
// AsyncPop3Client.swift
//
// Async POP3 client backed by AsyncTransport.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3Client {
    private enum AuthStep {
        case none
        case user
        case pass
    }

    private let transport: AsyncTransport
    private let queue = AsyncQueue<[UInt8]>()
    private var readerTask: Task<Void, Never>?
    private var decoder = Pop3ResponseDecoder()
    private var multilineDecoder = Pop3MultilineDecoder()
    private var authStep: AuthStep = .none

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
        case authenticated
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: Pop3Capabilities?
    public var protocolLogger: ProtocolLoggerType

    public init(transport: AsyncTransport, protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.transport = transport
        self.protocolLogger = protocolLogger
    }

    public func start() async throws {
        try await transport.start()
        state = .connected
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
    }

    public func beginAuthentication() {
        guard state == .connected else { return }
        state = .authenticating
    }

    public func endAuthentication() {
        if state == .authenticating {
            state = .authenticated
        }
    }

    public func handleAuthenticationResponse(_ response: Pop3Response) {
        guard state == .authenticating else { return }
        if response.isContinuation {
            state = .authenticating
            return
        }
        switch authStep {
        case .none:
            state = response.isSuccess ? .authenticated : .connected
        case .user:
            if response.isSuccess {
                state = .authenticating
                authStep = .pass
            } else {
                state = .connected
                authStep = .none
            }
        case .pass:
            state = response.isSuccess ? .authenticated : .connected
            authStep = .none
        }
    }

    public func makeCommand(_ kind: Pop3CommandKind) -> Pop3Command {
        kind.command()
    }

    @discardableResult
    public func send(_ kind: Pop3CommandKind) async throws -> [UInt8] {
        switch kind {
        case .user:
            beginAuthentication()
            authStep = .user
        case .pass:
            beginAuthentication()
            authStep = .pass
        case .auth(_, _), .apop(_, _):
            beginAuthentication()
            authStep = .none
        default:
            break
        }
        let command = makeCommand(kind)
        return try await send(command)
    }

    @discardableResult
    public func send(_ command: Pop3Command) async throws -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
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

    public func expectMultilineResponse() {
        multilineDecoder.expectMultiline()
    }

    public func nextResponses() async -> [Pop3Response]? {
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

    public func waitForResponse() async -> Pop3Response? {
        while let responses = await nextResponses() {
            if let first = responses.first {
                return first
            }
        }
        return nil
    }

    public func nextEvents() async -> [Pop3ResponseEvent] {
        guard let chunk = await queue.dequeue() else {
            return []
        }
        protocolLogger.logServer(chunk, offset: 0, count: chunk.count)
        return multilineDecoder.append(chunk)
    }

    public func nextChunk() async -> [UInt8] {
        guard let chunk = await queue.dequeue() else {
            return []
        }
        protocolLogger.logServer(chunk, offset: 0, count: chunk.count)
        return chunk
    }

    public func authenticate(user: String, password: String) async throws -> (user: Pop3Response?, pass: Pop3Response?) {
        beginAuthentication()
        authStep = .user
        let userCommand = makeCommand(.user(user))
        _ = try await send(userCommand)
        let userResponse = await waitForResponse()
        if let userResponse, !userResponse.isSuccess {
            handleAuthenticationResponse(userResponse)
            return (user: userResponse, pass: nil)
        }

        authStep = .pass
        let passCommand = makeCommand(.pass(password))
        _ = try await send(passCommand)
        let passResponse = await waitForResponse()
        if let passResponse {
            handleAuthenticationResponse(passResponse)
        }
        return (user: userResponse, pass: passResponse)
    }

    public func capa() async throws -> Pop3Capabilities? {
        expectMultilineResponse()
        let command = makeCommand(.capa)
        _ = try await send(command)

        while true {
            let events = await nextEvents()
            if events.isEmpty {
                return nil
            }
            for event in events {
                switch event {
                case let .single(response):
                    if !response.isSuccess {
                        return nil
                    }
                case .multiline:
                    if let parsed = Pop3Capabilities.parse(event) {
                        capabilities = parsed
                        return parsed
                    }
                }
            }
        }
    }
}
