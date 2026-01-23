//
// AsyncPop3Session.swift
//
// Higher-level async POP3 session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncPop3Session {
    private let client: AsyncPop3Client

    public init(transport: AsyncTransport) {
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

    public func stat() async throws -> Pop3StatResponse {
        _ = try await client.send(.stat)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        if let stat = Pop3StatResponse.parse(response) {
            return stat
        }
        throw SessionError.pop3Error(message: response.message)
    }

    public func list() async throws -> [Pop3ListItem] {
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

    public func state() async -> AsyncPop3Client.State {
        await client.state
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
}
