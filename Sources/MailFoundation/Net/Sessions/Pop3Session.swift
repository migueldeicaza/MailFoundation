//
// Pop3Session.swift
//
// Higher-level synchronous POP3 session helpers.
//

public final class Pop3Session {
    private let client: Pop3Client
    private let transport: Transport
    private let maxReads: Int

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.transport = transport
        self.client = Pop3Client(protocolLogger: protocolLogger)
        self.maxReads = maxReads
    }

    @discardableResult
    public func connect() throws -> Pop3Response {
        client.connect(transport: transport)
        guard let greeting = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard greeting.isSuccess else {
            throw SessionError.pop3Error(message: greeting.message)
        }
        return greeting
    }

    public func disconnect() {
        _ = client.send(.quit)
        transport.close()
    }

    public func authenticate(user: String, password: String) throws -> (user: Pop3Response, pass: Pop3Response) {
        _ = client.send(.user(user))
        try ensureWrite()
        guard let userResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard userResponse.isSuccess else {
            throw SessionError.pop3Error(message: userResponse.message)
        }

        _ = client.send(.pass(password))
        try ensureWrite()
        guard let passResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard passResponse.isSuccess else {
            throw SessionError.pop3Error(message: passResponse.message)
        }

        return (user: userResponse, pass: passResponse)
    }

    public func capability() throws -> Pop3Capabilities {
        client.expectMultilineResponse()
        _ = client.send(.capa)
        try ensureWrite()

        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw SessionError.pop3Error(message: response.message)
            }
            return Pop3Capabilities(rawLines: lines)
        }
        if case let .single(response) = event {
            throw SessionError.pop3Error(message: response.message)
        }
        throw SessionError.timeout
    }

    public func apop(user: String, digest: String) throws -> Pop3Response {
        _ = client.send(.apop(user, digest))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func auth(mechanism: String, initialResponse: String? = nil) throws -> Pop3Response {
        _ = client.send(.auth(mechanism, initialResponse: initialResponse))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func auth(
        mechanism: String,
        initialResponse: String? = nil,
        responder: (String) throws -> String
    ) throws -> Pop3Response {
        _ = client.send(.auth(mechanism, initialResponse: initialResponse))
        try ensureWrite()
        guard var response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }

        while response.isContinuation {
            let reply = try responder(response.message)
            _ = client.sendLine(reply)
            try ensureWrite()
            guard let next = client.waitForResponse(maxReads: maxReads) else {
                throw SessionError.timeout
            }
            response = next
        }

        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func noop() throws -> Pop3Response {
        try ensureAuthenticated()
        _ = client.send(.noop)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func rset() throws -> Pop3Response {
        try ensureAuthenticated()
        _ = client.send(.rset)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func dele(_ index: Int) throws -> Pop3Response {
        try ensureAuthenticated()
        _ = client.send(.dele(index))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func list(_ index: Int) throws -> Pop3ListItem {
        try ensureAuthenticated()
        _ = client.send(.list(index))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        if let item = Pop3ListItem.parseLine(response.message) {
            return item
        }
        throw SessionError.pop3Error(message: response.message)
    }

    public func uidl(_ index: Int) throws -> Pop3UidlItem {
        try ensureAuthenticated()
        _ = client.send(.uidl(index))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        if let item = Pop3UidlItem.parseLine(response.message) {
            return item
        }
        throw SessionError.pop3Error(message: response.message)
    }

    public func retr(_ index: Int) throws -> [String] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.retr(index))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw SessionError.pop3Error(message: response.message)
            }
            return lines
        }
        if case let .single(response) = event {
            throw SessionError.pop3Error(message: response.message)
        }
        throw SessionError.timeout
    }

    public func retrRaw(_ index: Int) throws -> [UInt8] {
        try ensureAuthenticated()
        _ = client.send(.retr(index))
        try ensureWrite()
        return try waitForMultilineData()
    }

    public func top(_ index: Int, lines: Int) throws -> [String] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw SessionError.pop3Error(message: response.message)
            }
            return lines
        }
        if case let .single(response) = event {
            throw SessionError.pop3Error(message: response.message)
        }
        throw SessionError.timeout
    }

    public func topRaw(_ index: Int, lines: Int) throws -> [UInt8] {
        try ensureAuthenticated()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        return try waitForMultilineData()
    }

    public func list() throws -> [Pop3ListItem] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.list(nil))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw SessionError.pop3Error(message: response.message)
            }
            return Pop3ListParser.parse(lines)
        }
        if case let .single(response) = event {
            throw SessionError.pop3Error(message: response.message)
        }
        throw SessionError.timeout
    }

    public func uidl() throws -> [Pop3UidlItem] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.uidl(nil))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw SessionError.pop3Error(message: response.message)
            }
            return Pop3UidlParser.parse(lines)
        }
        if case let .single(response) = event {
            throw SessionError.pop3Error(message: response.message)
        }
        throw SessionError.timeout
    }

    public func stat() throws -> Pop3StatResponse {
        try ensureAuthenticated()
        _ = client.send(.stat)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if let stat = Pop3StatResponse.parse(response) {
            return stat
        }
        throw SessionError.pop3Error(message: response.message)
    }

    public func last() throws -> Int {
        try ensureAuthenticated()
        _ = client.send(.last)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess, let value = Int(response.message) else {
            throw SessionError.pop3Error(message: response.message)
        }
        return value
    }

    public func retrBytes(_ index: Int) throws -> [UInt8] {
        let lines = try retr(index)
        return assembleBytes(from: lines)
    }

    public func topBytes(_ index: Int, lines: Int) throws -> [UInt8] {
        let result = try top(index, lines: lines)
        return assembleBytes(from: result)
    }

    public func startTls(validateCertificate: Bool = true) throws -> Pop3Response {
        guard let tlsTransport = transport as? StartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        _ = client.send(.stls)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    private func waitForMultilineEvent() throws -> Pop3ResponseEvent {
        var reads = 0
        while reads < maxReads {
            let events = client.receiveMultiline()
            if let event = events.first {
                return event
            }
            reads += 1
        }
        throw SessionError.timeout
    }

    private func waitForMultilineData() throws -> [UInt8] {
        var decoder = Pop3MultilineByteDecoder()
        decoder.expectMultiline()
        var reads = 0
        while reads < maxReads {
            let bytes = transport.readAvailable(maxLength: 4096)
            if bytes.isEmpty {
                reads += 1
                continue
            }
            client.protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
            let events = decoder.append(bytes)
            for event in events {
                switch event {
                case let .single(response):
                    throw SessionError.pop3Error(message: response.message)
                case let .multiline(response, data):
                    guard response.isSuccess else {
                        throw SessionError.pop3Error(message: response.message)
                    }
                    return data
                }
            }
        }
        throw SessionError.timeout
    }

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }

    private func ensureAuthenticated() throws {
        guard client.state == .authenticated else {
            throw SessionError.invalidState(expected: .authenticated, actual: state)
        }
    }

    private func assembleBytes(from lines: [String]) -> [UInt8] {
        guard !lines.isEmpty else { return [] }
        let joined = lines.joined(separator: "\r\n")
        return Array(joined.utf8)
    }
}

extension Pop3Session: MailService {
    public typealias ConnectResponse = Pop3Response

    public var state: MailServiceState {
        switch client.state {
        case .disconnected:
            return .disconnected
        case .connected, .authenticating:
            return .connected
        case .authenticated:
            return .authenticated
        }
    }

    public var isConnected: Bool { client.isConnected }

    public var isAuthenticated: Bool { client.state == .authenticated }
}
