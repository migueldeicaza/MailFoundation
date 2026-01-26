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
            throw pop3CommandError(from: greeting)
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
            throw pop3CommandError(from: userResponse)
        }

        _ = client.send(.pass(password))
        try ensureWrite()
        guard let passResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard passResponse.isSuccess else {
            throw pop3CommandError(from: passResponse)
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
                throw pop3CommandError(from: response)
            }
            return Pop3Capabilities(rawLines: lines)
        }
        if case let .single(response) = event {
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
        }
        return response
    }

    public func authenticate(_ authentication: Pop3Authentication) throws -> Pop3Response {
        if let responder = authentication.responder {
            return try auth(
                mechanism: authentication.mechanism,
                initialResponse: authentication.initialResponse,
                responder: responder
            )
        }
        return try auth(
            mechanism: authentication.mechanism,
            initialResponse: authentication.initialResponse
        )
    }

    public func authenticateCramMd5(user: String, password: String) throws -> Pop3Response {
        guard let authentication = Pop3Sasl.cramMd5(username: user, password: password) else {
            throw SessionError.pop3Error(message: "CRAM-MD5 is not available.")
        }
        return try authenticate(authentication)
    }

    public func authenticateXoauth2(user: String, accessToken: String) throws -> Pop3Response {
        let authentication = Pop3Sasl.xoauth2(username: user, accessToken: accessToken)
        return try authenticate(authentication)
    }

    public func authenticateSasl(
        user: String,
        password: String,
        capabilities: Pop3Capabilities? = nil,
        mechanisms: [String]? = nil
    ) throws -> Pop3Response {
        let availableMechanisms: [String]
        if let mechanisms {
            availableMechanisms = mechanisms
        } else if let capabilities {
            availableMechanisms = capabilities.saslMechanisms()
        } else {
            availableMechanisms = try capability().saslMechanisms()
        }

        guard let authentication = Pop3Sasl.chooseAuthentication(
            username: user,
            password: password,
            mechanisms: availableMechanisms
        ) else {
            throw SessionError.pop3Error(message: "No supported SASL mechanisms.")
        }
        return try authenticate(authentication)
    }

    public func authenticateSasl(
        user: String,
        accessToken: String,
        capabilities: Pop3Capabilities? = nil,
        mechanisms: [String]? = nil
    ) throws -> Pop3Response {
        let availableMechanisms: [String]
        if let mechanisms {
            availableMechanisms = mechanisms
        } else if let capabilities {
            availableMechanisms = capabilities.saslMechanisms()
        } else {
            availableMechanisms = try capability().saslMechanisms()
        }

        guard availableMechanisms.contains(where: { $0.caseInsensitiveCompare("XOAUTH2") == .orderedSame }) else {
            throw SessionError.pop3Error(message: "XOAUTH2 is not supported.")
        }
        return try authenticateXoauth2(user: user, accessToken: accessToken)
    }

    public func noop() throws -> Pop3Response {
        try ensureAuthenticated()
        _ = client.send(.noop)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
        }
        if let item = Pop3ListItem.parseLine(response.message) {
            return item
        }
        throw pop3CommandError(from: response)
    }

    public func uidl(_ index: Int) throws -> Pop3UidlItem {
        try ensureAuthenticated()
        _ = client.send(.uidl(index))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw pop3CommandError(from: response)
        }
        if let item = Pop3UidlItem.parseLine(response.message) {
            return item
        }
        throw pop3CommandError(from: response)
    }

    public func retr(_ index: Int) throws -> [String] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.retr(index))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw pop3CommandError(from: response)
            }
            return lines
        }
        if case let .single(response) = event {
            throw pop3CommandError(from: response)
        }
        throw SessionError.timeout
    }

    public func retrData(_ index: Int) throws -> Pop3MessageData {
        try ensureAuthenticated()
        _ = client.send(.retr(index))
        try ensureWrite()
        let (response, data) = try waitForMultilineDataResponse()
        return Pop3MessageData(response: response, data: data)
    }

    public func retrRaw(_ index: Int) throws -> [UInt8] {
        try ensureAuthenticated()
        _ = client.send(.retr(index))
        try ensureWrite()
        return try waitForMultilineData()
    }

    public func retrStream(_ index: Int, sink: ([UInt8]) throws -> Void) throws {
        try ensureAuthenticated()
        _ = client.send(.retr(index))
        try ensureWrite()
        try streamMultilineData(into: sink)
    }

    public func top(_ index: Int, lines: Int) throws -> [String] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw pop3CommandError(from: response)
            }
            return lines
        }
        if case let .single(response) = event {
            throw pop3CommandError(from: response)
        }
        throw SessionError.timeout
    }

    public func topData(_ index: Int, lines: Int) throws -> Pop3MessageData {
        try ensureAuthenticated()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        let (response, data) = try waitForMultilineDataResponse()
        return Pop3MessageData(response: response, data: data)
    }

    public func topRaw(_ index: Int, lines: Int) throws -> [UInt8] {
        try ensureAuthenticated()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        return try waitForMultilineData()
    }

    public func topStream(_ index: Int, lines: Int, sink: ([UInt8]) throws -> Void) throws {
        try ensureAuthenticated()
        _ = client.send(.top(index, lines: lines))
        try ensureWrite()
        try streamMultilineData(into: sink)
    }

    public func list() throws -> [Pop3ListItem] {
        try ensureAuthenticated()
        client.expectMultilineResponse()
        _ = client.send(.list(nil))
        try ensureWrite()
        let event = try waitForMultilineEvent()
        if case let .multiline(response, lines) = event {
            guard response.isSuccess else {
                throw pop3CommandError(from: response)
            }
            return Pop3ListParser.parse(lines)
        }
        if case let .single(response) = event {
            throw pop3CommandError(from: response)
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
                throw pop3CommandError(from: response)
            }
            return Pop3UidlParser.parse(lines)
        }
        if case let .single(response) = event {
            throw pop3CommandError(from: response)
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
        throw pop3CommandError(from: response)
    }

    public func last() throws -> Int {
        try ensureAuthenticated()
        _ = client.send(.last)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess, let value = Int(response.message) else {
            throw pop3CommandError(from: response)
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
            throw pop3CommandError(from: response)
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

    private func waitForMultilineDataResponse() throws -> (Pop3Response, [UInt8]) {
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
                    throw pop3CommandError(from: response)
                case let .multiline(response, data):
                    guard response.isSuccess else {
                        throw pop3CommandError(from: response)
                    }
                    return (response, data)
                }
            }
        }
        throw SessionError.timeout
    }

    private func waitForMultilineData() throws -> [UInt8] {
        let (_, data) = try waitForMultilineDataResponse()
        return data
    }

    private func streamMultilineData(into sink: ([UInt8]) throws -> Void) throws {
        var lineBuffer = ByteLineBuffer()
        var reads = 0
        var awaitingStatus = true
        var isFirstLine = true

        while reads < maxReads {
            let bytes = transport.readAvailable(maxLength: 4096)
            if bytes.isEmpty {
                reads += 1
                continue
            }
            client.protocolLogger.logServer(bytes, offset: 0, count: bytes.count)
            let lines = lineBuffer.append(bytes)
            for line in lines {
                if awaitingStatus {
                    let text = String(decoding: line, as: UTF8.self)
                    if let response = Pop3Response.parse(text) {
                        if response.isSuccess {
                            awaitingStatus = false
                            continue
                        }
                        throw pop3CommandError(from: response)
                    }
                    continue
                }

                if line == [0x2e] {
                    return
                }

                let dataLine: [UInt8]
                if line.count >= 2, line[0] == 0x2e, line[1] == 0x2e {
                    dataLine = Array(line.dropFirst())
                } else {
                    dataLine = line
                }

                if isFirstLine {
                    try sink(dataLine)
                    isFirstLine = false
                } else {
                    var chunk: [UInt8] = [0x0D, 0x0A]
                    chunk.append(contentsOf: dataLine)
                    try sink(chunk)
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

    private func pop3CommandError(from response: Pop3Response) -> Pop3CommandError {
        Pop3CommandError(statusText: response.message)
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
