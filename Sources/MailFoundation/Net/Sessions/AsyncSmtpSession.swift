//
// AsyncSmtpSession.swift
//
// Higher-level async SMTP session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpSession {
    private let client: AsyncSmtpClient

    public init(transport: AsyncTransport) {
        self.client = AsyncSmtpClient(transport: transport)
    }

    public static func make(host: String, port: UInt16, backend: AsyncTransportBackend = .network) throws -> AsyncSmtpSession {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncSmtpSession(transport: transport)
    }

    @discardableResult
    public func connect() async throws -> SmtpResponse? {
        try await client.start()
        return await client.waitForResponse()
    }

    public func disconnect() async {
        _ = try? await client.send(.quit)
        await client.stop()
    }

    public func ehlo(domain: String) async throws -> SmtpCapabilities? {
        try await client.ehlo(domain: domain)
    }

    public func helo(domain: String) async throws -> SmtpResponse? {
        _ = try await client.send(.helo(domain))
        return await client.waitForResponse()
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) async throws -> SmtpResponse? {
        try await client.authenticate(mechanism: mechanism, initialResponse: initialResponse)
    }

    public func sendData(_ message: [UInt8]) async throws -> SmtpResponse? {
        try await client.sendData(message)
    }

    public func sendMail(from: String, to recipients: [String], data: [UInt8]) async throws -> SmtpResponse {
        _ = try await client.send(.mailFrom(from))
        guard let mailResponse = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            _ = try await client.send(.rcptTo(recipient))
            guard let rcptResponse = await client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard rcptResponse.isSuccess else {
                throw SessionError.smtpError(code: rcptResponse.code, message: rcptResponse.lines.joined(separator: " "))
            }
        }

        if let response = try await client.sendData(data) {
            if response.isSuccess {
                return response
            }
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }

        throw SessionError.timeout
    }

    public func state() async -> AsyncSmtpClient.State {
        await client.state
    }

    public func capabilities() async -> SmtpCapabilities? {
        await client.capabilities
    }
}
