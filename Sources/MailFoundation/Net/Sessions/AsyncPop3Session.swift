//
// AsyncPop3Session.swift
//
// Higher-level async POP3 session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3Session {
    private let client: AsyncPop3Client
    private let transport: AsyncTransport

    public init(transport: AsyncTransport) {
        self.transport = transport
        self.client = AsyncPop3Client(transport: transport)
    }

    public static func make(host: String, port: UInt16, backend: AsyncTransportBackend = .network) throws -> AsyncPop3Session {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncPop3Session(transport: transport)
    }

    @discardableResult
    public func connect() async throws -> Pop3Response? {
        try await client.start()
        return await client.waitForResponse()
    }

    public func disconnect() async {
        _ = try? await client.send(.quit)
        await client.stop()
    }

    public func capability() async throws -> Pop3Capabilities? {
        try await client.capa()
    }

    public func authenticate(user: String, password: String) async throws -> (user: Pop3Response?, pass: Pop3Response?) {
        try await client.authenticate(user: user, password: password)
    }

    public func apop(user: String, digest: String) async throws -> Pop3Response? {
        _ = try await client.send(.apop(user, digest))
        return await client.waitForResponse()
    }

    public func auth(mechanism: String, initialResponse: String? = nil) async throws -> Pop3Response? {
        _ = try await client.send(.auth(mechanism, initialResponse: initialResponse))
        return await client.waitForResponse()
    }

    public func auth(
        mechanism: String,
        initialResponse: String? = nil,
        responder: @Sendable (String) async throws -> String
    ) async throws -> Pop3Response? {
        _ = try await client.send(.auth(mechanism, initialResponse: initialResponse))
        guard var response = await client.waitForResponse() else {
            throw SessionError.timeout
        }

        while response.isContinuation {
            let reply = try await responder(response.message)
            _ = try await client.sendLine(reply)
            guard let next = await client.waitForResponse() else {
                throw SessionError.timeout
            }
            response = next
        }

        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func noop() async throws -> Pop3Response? {
        try await ensureAuthenticated()
        _ = try await client.send(.noop)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func rset() async throws -> Pop3Response? {
        try await ensureAuthenticated()
        _ = try await client.send(.rset)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func dele(_ index: Int) async throws -> Pop3Response? {
        try await ensureAuthenticated()
        _ = try await client.send(.dele(index))
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        return response
    }

    public func list(_ index: Int) async throws -> Pop3ListItem {
        try await ensureAuthenticated()
        _ = try await client.send(.list(index))
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess, let item = Pop3ListItem.parseLine(response.message) else {
            throw SessionError.pop3Error(message: response.message)
        }
        return item
    }

    public func uidl(_ index: Int) async throws -> Pop3UidlItem {
        try await ensureAuthenticated()
        _ = try await client.send(.uidl(index))
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess, let item = Pop3UidlItem.parseLine(response.message) else {
            throw SessionError.pop3Error(message: response.message)
        }
        return item
    }

    public func retr(_ index: Int) async throws -> [String] {
        try await ensureAuthenticated()
        await client.expectMultilineResponse()
        _ = try await client.send(.retr(index))
        let event = try await waitForMultilineEvent()
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

    public func retrData(_ index: Int) async throws -> Pop3MessageData {
        try await ensureAuthenticated()
        _ = try await client.send(.retr(index))
        let (response, data) = try await waitForMultilineDataResponse()
        return Pop3MessageData(response: response, data: data)
    }

    public func retrRaw(_ index: Int) async throws -> [UInt8] {
        try await ensureAuthenticated()
        _ = try await client.send(.retr(index))
        return try await waitForMultilineData()
    }

    public func retrStream(
        _ index: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await ensureAuthenticated()
        _ = try await client.send(.retr(index))
        try await streamMultilineData(into: sink)
    }

    public func top(_ index: Int, lines: Int) async throws -> [String] {
        try await ensureAuthenticated()
        await client.expectMultilineResponse()
        _ = try await client.send(.top(index, lines: lines))
        let event = try await waitForMultilineEvent()
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

    public func topData(_ index: Int, lines: Int) async throws -> Pop3MessageData {
        try await ensureAuthenticated()
        _ = try await client.send(.top(index, lines: lines))
        let (response, data) = try await waitForMultilineDataResponse()
        return Pop3MessageData(response: response, data: data)
    }

    public func topRaw(_ index: Int, lines: Int) async throws -> [UInt8] {
        try await ensureAuthenticated()
        _ = try await client.send(.top(index, lines: lines))
        return try await waitForMultilineData()
    }

    public func topStream(
        _ index: Int,
        lines: Int,
        sink: @Sendable ([UInt8]) async throws -> Void
    ) async throws {
        try await ensureAuthenticated()
        _ = try await client.send(.top(index, lines: lines))
        try await streamMultilineData(into: sink)
    }

    public func stat() async throws -> Pop3StatResponse {
        try await ensureAuthenticated()
        _ = try await client.send(.stat)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        if let stat = Pop3StatResponse.parse(response) {
            return stat
        }
        throw SessionError.pop3Error(message: response.message)
    }

    public func last() async throws -> Int {
        try await ensureAuthenticated()
        _ = try await client.send(.last)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess, let value = Int(response.message) else {
            throw SessionError.pop3Error(message: response.message)
        }
        return value
    }

    public func retrBytes(_ index: Int) async throws -> [UInt8] {
        let lines = try await retr(index)
        return assembleBytes(from: lines)
    }

    public func topBytes(_ index: Int, lines: Int) async throws -> [UInt8] {
        let result = try await top(index, lines: lines)
        return assembleBytes(from: result)
    }

    public func list() async throws -> [Pop3ListItem] {
        try await ensureAuthenticated()
        await client.expectMultilineResponse()
        _ = try await client.send(.list(nil))
        let event = try await waitForMultilineEvent()
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

    public func uidl() async throws -> [Pop3UidlItem] {
        try await ensureAuthenticated()
        await client.expectMultilineResponse()
        _ = try await client.send(.uidl(nil))
        let event = try await waitForMultilineEvent()
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

    public func startTls(validateCertificate: Bool = true) async throws -> Pop3Response {
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        _ = try await client.send(.stls)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.pop3Error(message: response.message)
        }
        try await tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    public func capabilities() async -> Pop3Capabilities? {
        await client.capabilities
    }

    private func waitForMultilineEvent(maxEmptyReads: Int = 10) async throws -> Pop3ResponseEvent {
        var emptyReads = 0
        while emptyReads < maxEmptyReads {
            let events = await client.nextEvents()
            if let event = events.first {
                return event
            }
            emptyReads += 1
        }
        throw SessionError.timeout
    }

    private func waitForMultilineDataResponse(maxEmptyReads: Int = 10) async throws -> (Pop3Response, [UInt8]) {
        var decoder = Pop3MultilineByteDecoder()
        decoder.expectMultiline()
        var emptyReads = 0
        while emptyReads < maxEmptyReads {
            let chunk = await client.nextChunk()
            if chunk.isEmpty {
                emptyReads += 1
                continue
            }
            let events = decoder.append(chunk)
            for event in events {
                switch event {
                case let .single(response):
                    throw SessionError.pop3Error(message: response.message)
                case let .multiline(response, data):
                    guard response.isSuccess else {
                        throw SessionError.pop3Error(message: response.message)
                    }
                    return (response, data)
                }
            }
        }
        throw SessionError.timeout
    }

    private func waitForMultilineData(maxEmptyReads: Int = 10) async throws -> [UInt8] {
        let (_, data) = try await waitForMultilineDataResponse(maxEmptyReads: maxEmptyReads)
        return data
    }

    private func streamMultilineData(
        into sink: @Sendable ([UInt8]) async throws -> Void,
        maxEmptyReads: Int = 10
    ) async throws {
        var lineBuffer = ByteLineBuffer()
        var emptyReads = 0
        var awaitingStatus = true
        var isFirstLine = true

        while emptyReads < maxEmptyReads {
            let chunk = await client.nextChunk()
            if chunk.isEmpty {
                emptyReads += 1
                continue
            }

            let lines = lineBuffer.append(chunk)
            for line in lines {
                if awaitingStatus {
                    let text = String(decoding: line, as: UTF8.self)
                    if let response = Pop3Response.parse(text) {
                        if response.isSuccess {
                            awaitingStatus = false
                            continue
                        }
                        throw SessionError.pop3Error(message: response.message)
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
                    try await sink(dataLine)
                    isFirstLine = false
                } else {
                    var chunk: [UInt8] = [0x0D, 0x0A]
                    chunk.append(contentsOf: dataLine)
                    try await sink(chunk)
                }
            }
        }

        throw SessionError.timeout
    }

    private func ensureAuthenticated() async throws {
        let clientState = await client.state
        guard clientState == .authenticated else {
            let mailState: MailServiceState = clientState == .disconnected ? .disconnected : .connected
            throw SessionError.invalidState(expected: .authenticated, actual: mailState)
        }
    }

    private func assembleBytes(from lines: [String]) -> [UInt8] {
        guard !lines.isEmpty else { return [] }
        let joined = lines.joined(separator: "\r\n")
        return Array(joined.utf8)
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension AsyncPop3Session: AsyncMailService {
    public typealias ConnectResponse = Pop3Response?

    public var state: MailServiceState {
        get async {
            let clientState = await client.state
            switch clientState {
            case .disconnected:
                return .disconnected
            case .connected, .authenticating:
                return .connected
            case .authenticated:
                return .authenticated
            }
        }
    }

    public var isConnected: Bool {
        get async {
            let clientState = await client.state
            return clientState != .disconnected
        }
    }

    public var isAuthenticated: Bool {
        get async { await client.state == .authenticated }
    }
}
