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

    public func list() throws -> [Pop3ListItem] {
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

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }
}
