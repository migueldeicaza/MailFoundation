//
// ImapClient.swift
//
// Minimal scaffolding for IMAP client.
//

import Foundation

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

    public enum State: Sendable {
        case disconnected
        case connected
        case authenticating
        case authenticated
        case selected
    }

    public private(set) var state: State = .disconnected
    public private(set) var capabilities: ImapCapabilities?
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
    }

    public func makeCommand(_ name: String, arguments: String? = nil) -> ImapCommand {
        let tag = tagGenerator.nextTag()
        return ImapCommand(tag: tag, name: name, arguments: arguments)
    }

    public func makeCommand(_ kind: ImapCommandKind) -> ImapCommand {
        let tag = tagGenerator.nextTag()
        return kind.command(tag: tag)
    }

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

    @discardableResult
    public func send(_ command: ImapCommand) -> [UInt8] {
        let bytes = Array(command.serialized.utf8)
        protocolLogger.logClient(bytes, offset: 0, count: bytes.count)
        let written = transport?.write(bytes) ?? 0
        lastWriteSucceeded = written == bytes.count
        return bytes
    }

    public func handleIncoming(_ bytes: [UInt8]) -> [ImapResponse] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let responses = decoder.append(bytes)
        handleResponses(responses)
        return responses
    }

    public func handleIncomingWithLiterals(_ bytes: [UInt8]) -> [ImapLiteralMessage] {
        protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
        let messages = literalDecoder.append(bytes)
        for message in messages {
            if let response = message.response {
                handleResponse(response)
            }
            if let parsed = ImapCapabilities.parse(from: message.line) {
                capabilities = parsed
            }
        }
        return messages
    }

    public func handleResponses(_ responses: [ImapResponse]) {
        for response in responses {
            handleResponse(response)
        }
    }

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

    public func receive() -> [ImapResponse] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else { return [] }
        return handleIncoming(bytes)
    }

    public func receiveWithLiterals() -> [ImapLiteralMessage] {
        guard let transport else { return [] }
        let bytes = transport.readAvailable(maxLength: 4096)
        guard !bytes.isEmpty else { return [] }
        return handleIncomingWithLiterals(bytes)
    }

    public func waitForTagged(_ tag: String, maxReads: Int = 10) -> ImapResponse? {
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

    public func execute(_ kind: ImapCommandKind, maxReads: Int = 10) -> ImapResponse? {
        let command = send(kind)
        return waitForTagged(command.tag, maxReads: maxReads)
    }
}
