//
// Pop3Client.swift
//
// Minimal scaffolding for POP3 client.
//

import Foundation

public final class Pop3Client {
    private enum AuthStep {
        case none
        case user
        case pass
    }

    private let detector = Pop3AuthenticationSecretDetector()
    private var decoder = Pop3ResponseDecoder()
    private var multilineDecoder = Pop3MultilineDecoder()
    private var transport: Transport?
    private var authStep: AuthStep = .none

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
        case authenticated
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: Pop3Capabilities?
    public private(set) var lastWriteSucceeded: Bool = true

    public var protocolLogger: ProtocolLoggerType {
        didSet {
            protocolLogger.authenticationSecretDetector = detector
        }
    }

    public private(set) var isConnected: Bool = false

    public init(protocolLogger: ProtocolLoggerType = NullProtocolLogger()) {
        self.protocolLogger = protocolLogger
        self.protocolLogger.authenticationSecretDetector = detector
    }

    public func connect(to uri: URL) {
        protocolLogger.logConnect(uri)
        isConnected = true
        state = .connected
    }

    public func connect(transport: Transport) {
        self.transport = transport
        transport.open()
        isConnected = true
        state = .connected
    }

    public func disconnect() {
        isConnected = false
        state = .disconnected
    }

    public func beginAuthentication() {
        guard isConnected else { return }
        detector.isAuthenticating = true
        state = .authenticating
    }

    public func endAuthentication() {
        detector.isAuthenticating = false
        state = isConnected ? .authenticated : .disconnected
        authStep = .none
    }

    public func handleAuthenticationResponse(_ response: Pop3Response) {
        detector.isAuthenticating = false
        switch authStep {
        case .none:
            state = response.isSuccess ? .authenticated : .connected
        case .user:
            if response.isSuccess {
                detector.isAuthenticating = true
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

    public func makeCommand(_ keyword: String, arguments: String? = nil) -> Pop3Command {
        Pop3Command(keyword: keyword, arguments: arguments)
    }

    public func makeCommand(_ kind: Pop3CommandKind) -> Pop3Command {
        kind.command()
    }

    @discardableResult
    public func send(_ kind: Pop3CommandKind) -> [UInt8] {
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
        return send(makeCommand(kind))
    }

    @discardableResult
    public func send(_ command: Pop3Command) -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        let written = transport?.write(bytes) ?? 0
        lastWriteSucceeded = written == bytes.count
        return bytes
    }

    public func expectMultilineResponse() {
        multilineDecoder.expectMultiline()
    }

    public func beginCapabilityQuery() {
        expectMultilineResponse()
        _ = send(makeCommand(.capa))
    }

    public func handleIncoming(_ bytes: [UInt8]) -> [Pop3Response] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let responses = decoder.append(bytes)
        handleResponses(responses)
        return responses
    }

    public func handleIncomingMultiline(_ bytes: [UInt8]) -> [Pop3ResponseEvent] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        return multilineDecoder.append(bytes)
    }

    public func handleCapabilitiesEvent(_ event: Pop3ResponseEvent) -> Pop3Capabilities? {
        let parsed = Pop3Capabilities.parse(event)
        if let parsed {
            capabilities = parsed
        }
        return parsed
    }

    public func handleResponses(_ responses: [Pop3Response]) {
        guard !responses.isEmpty else { return }
        for response in responses where state == .authenticating {
            handleAuthenticationResponse(response)
        }
    }

    public func waitForResponse(maxReads: Int = 10) -> Pop3Response? {
        var reads = 0
        while reads < maxReads {
            let responses = receive()
            if let first = responses.first {
                return first
            }
            reads += 1
        }
        return nil
    }

    public func receive() -> [Pop3Response] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else { return [] }
        return handleIncoming(bytes)
    }

    public func receiveMultiline() -> [Pop3ResponseEvent] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else { return [] }
        return handleIncomingMultiline(bytes)
    }
}
