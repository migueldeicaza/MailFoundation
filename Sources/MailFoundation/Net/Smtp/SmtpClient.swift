//
// SmtpClient.swift
//
// Minimal scaffolding for SMTP client.
//

import Foundation

public final class SmtpClient {
    private let detector = SmtpAuthenticationSecretDetector()
    private var decoder = SmtpResponseDecoder()
    private var transport: Transport?

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: SmtpCapabilities?
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
        state = isConnected ? .connected : .disconnected
    }

    public func handleAuthenticationResponse(_ response: SmtpResponse) {
        guard state == .authenticating else { return }
        detector.isAuthenticating = false
        if response.code >= 200 && response.code < 300 {
            state = .connected
        } else if response.code >= 400 {
            state = .connected
        }
    }

    public func makeCommand(_ keyword: String, arguments: String? = nil) -> SmtpCommand {
        SmtpCommand(keyword: keyword, arguments: arguments)
    }

    public func makeCommand(_ kind: SmtpCommandKind) -> SmtpCommand {
        kind.command()
    }

    @discardableResult
    public func send(_ kind: SmtpCommandKind) -> [UInt8] {
        if case .auth = kind {
            beginAuthentication()
        }
        return send(makeCommand(kind))
    }

    @discardableResult
    public func send(_ command: SmtpCommand) -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        let written = transport?.write(bytes) ?? 0
        lastWriteSucceeded = written == bytes.count
        return bytes
    }

    @discardableResult
    public func handleEhloResponse(_ response: SmtpResponse) -> SmtpCapabilities? {
        let parsed = SmtpCapabilities.parseEhlo(response)
        if let parsed {
            capabilities = parsed
        }
        return parsed
    }

    public func handleIncoming(_ bytes: [UInt8]) -> [SmtpResponse] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let responses = decoder.append(bytes)
        handleResponses(responses)
        return responses
    }

    public func waitForResponse(maxReads: Int = 10) -> SmtpResponse? {
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

    public func sendData(_ message: [UInt8], maxReads: Int = 10) -> SmtpResponse? {
        _ = send(.data)
        guard let intermediate = waitForResponse(maxReads: maxReads) else {
            return nil
        }
        guard intermediate.code == 354 else {
            return intermediate
        }

        let payload = SmtpDataWriter.prepare(message)
        protocolLogger.logClient(payload, offset: 0, count: payload.count)
        let written = transport?.write(payload) ?? 0
        lastWriteSucceeded = written == payload.count
        return waitForResponse(maxReads: maxReads)
    }

    public func handleResponses(_ responses: [SmtpResponse]) {
        guard !responses.isEmpty else { return }
        for response in responses where state == .authenticating {
            handleAuthenticationResponse(response)
        }
    }

    public func receive() -> [SmtpResponse] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else { return [] }
        return handleIncoming(bytes)
    }
}
