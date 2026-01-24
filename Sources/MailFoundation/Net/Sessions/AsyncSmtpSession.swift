//
// AsyncSmtpSession.swift
//
// Higher-level async SMTP session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpSession {
    private let client: AsyncSmtpClient
    private let transport: AsyncTransport

    public init(transport: AsyncTransport) {
        self.transport = transport
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
        return try requireSuccess(await client.waitForResponse())
    }

    public func noop() async throws -> SmtpResponse? {
        _ = try await client.send(.noop)
        return try requireSuccess(await client.waitForResponse())
    }

    public func rset() async throws -> SmtpResponse? {
        _ = try await client.send(.rset)
        return try requireSuccess(await client.waitForResponse())
    }

    public func vrfy(_ argument: String) async throws -> SmtpResponse? {
        _ = try await client.send(.vrfy(argument))
        return try requireSuccess(await client.waitForResponse())
    }

    public func vrfyResult(_ argument: String) async throws -> SmtpVrfyResult {
        guard let response = try await vrfy(argument) else {
            throw SessionError.timeout
        }
        return SmtpVrfyResult(response: response)
    }

    public func expn(_ argument: String) async throws -> SmtpResponse? {
        _ = try await client.send(.expn(argument))
        return try requireSuccess(await client.waitForResponse())
    }

    public func expnResult(_ argument: String) async throws -> SmtpExpnResult {
        guard let response = try await expn(argument) else {
            throw SessionError.timeout
        }
        return SmtpExpnResult(response: response)
    }

    public func help(_ argument: String? = nil) async throws -> SmtpResponse? {
        _ = try await client.send(.help(argument))
        return try requireSuccess(await client.waitForResponse())
    }

    public func helpResult(_ argument: String? = nil) async throws -> SmtpHelpResult {
        guard let response = try await help(argument) else {
            throw SessionError.timeout
        }
        return SmtpHelpResult(response: response)
    }

    private func requireSuccess(_ response: SmtpResponse?) throws -> SmtpResponse {
        guard let response else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }
        return response
    }

    public func mailFrom(_ address: String) async throws -> SmtpResponse? {
        _ = try await client.send(.mailFrom(address))
        return await client.waitForResponse()
    }

    public func mailFrom(_ address: String, parameters: SmtpMailFromParameters) async throws -> SmtpResponse? {
        _ = try await client.send(.mailFromParameters(address, parameters))
        return await client.waitForResponse()
    }

    public func rcptTo(_ address: String) async throws -> SmtpResponse? {
        _ = try await client.send(.rcptTo(address))
        return await client.waitForResponse()
    }

    public func rcptTo(_ address: String, parameters: SmtpRcptToParameters) async throws -> SmtpResponse? {
        _ = try await client.send(.rcptToParameters(address, parameters))
        return await client.waitForResponse()
    }

    public func data(_ message: [UInt8]) async throws -> SmtpResponse? {
        try await client.sendData(message)
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) async throws -> SmtpResponse? {
        try await client.authenticate(mechanism: mechanism, initialResponse: initialResponse)
    }

    public func authenticate(
        mechanism: String,
        initialResponse: String? = nil,
        responder: @Sendable (String) async throws -> String
    ) async throws -> SmtpResponse {
        _ = try await client.send(.auth(mechanism, initialResponse: initialResponse))
        guard var response = await client.waitForResponse() else {
            throw SessionError.timeout
        }

        while response.code == 334 {
            let challenge = response.lines.first ?? ""
            let reply = try await responder(challenge)
            _ = try await client.sendLine(reply)
            guard let next = await client.waitForResponse() else {
                throw SessionError.timeout
            }
            response = next
        }

        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
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

    public func sendMail(
        from: String,
        to recipients: [String],
        data: [UInt8],
        mailParameters: SmtpMailFromParameters?,
        rcptParameters: SmtpRcptToParameters?
    ) async throws -> SmtpResponse {
        if let mailParameters {
            _ = try await client.send(.mailFromParameters(from, mailParameters))
        } else {
            _ = try await client.send(.mailFrom(from))
        }
        guard let mailResponse = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            if let rcptParameters {
                _ = try await client.send(.rcptToParameters(recipient, rcptParameters))
            } else {
                _ = try await client.send(.rcptTo(recipient))
            }
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

    public func sendMailPipelined(
        from: String,
        to recipients: [String],
        data: [UInt8],
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        if let mailParameters {
            _ = try await client.send(.mailFromParameters(from, mailParameters))
        } else {
            _ = try await client.send(.mailFrom(from))
        }

        for recipient in recipients {
            if let rcptParameters {
                _ = try await client.send(.rcptToParameters(recipient, rcptParameters))
            } else {
                _ = try await client.send(.rcptTo(recipient))
            }
        }

        guard let mailResponse = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for _ in recipients {
            guard let rcptResponse = await client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard rcptResponse.isSuccess else {
                throw SessionError.smtpError(code: rcptResponse.code, message: rcptResponse.lines.joined(separator: " "))
            }
        }

        if let dataResponse = try await client.sendData(data) {
            if dataResponse.isSuccess {
                return dataResponse
            }
            throw SessionError.smtpError(code: dataResponse.code, message: dataResponse.lines.joined(separator: " "))
        }

        throw SessionError.timeout
    }

    public func sendBdat(_ data: [UInt8], last: Bool) async throws -> SmtpResponse {
        _ = try await client.send(.bdat(data.count, last: last))
        _ = try await client.sendRaw(data)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }
        return response
    }

    public func sendMailChunked(
        from: String,
        to recipients: [String],
        data: [UInt8],
        chunkSize: Int = 4096,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        let size = max(1, chunkSize)
        if let mailParameters {
            _ = try await client.send(.mailFromParameters(from, mailParameters))
        } else {
            _ = try await client.send(.mailFrom(from))
        }
        guard let mailResponse = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            if let rcptParameters {
                _ = try await client.send(.rcptToParameters(recipient, rcptParameters))
            } else {
                _ = try await client.send(.rcptTo(recipient))
            }
            guard let rcptResponse = await client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard rcptResponse.isSuccess else {
                throw SessionError.smtpError(code: rcptResponse.code, message: rcptResponse.lines.joined(separator: " "))
            }
        }

        var response = mailResponse
        if !data.isEmpty {
            var offset = 0
            while offset < data.count {
                let end = min(offset + size, data.count)
                let chunk = Array(data[offset..<end])
                let isLast = end == data.count
                response = try await sendBdat(chunk, last: isLast)
                offset = end
            }
        }
        return response
    }

    public func startTls(validateCertificate: Bool = true) async throws -> SmtpResponse {
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        _ = try await client.send(.starttls)
        guard let response = await client.waitForResponse() else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }
        try await tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    public func etrn(_ argument: String) async throws -> SmtpResponse? {
        _ = try await client.send(.etrn(argument))
        return await client.waitForResponse()
    }

    public func capabilities() async -> SmtpCapabilities? {
        await client.capabilities
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension AsyncSmtpSession: AsyncMailService {
    public typealias ConnectResponse = SmtpResponse?

    public var state: MailServiceState {
        get async {
            let clientState = await client.state
            switch clientState {
            case .disconnected:
                return .disconnected
            case .connected:
                return (await client.isAuthenticated) ? .authenticated : .connected
            case .authenticating:
                return .connected
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
        get async { await client.isAuthenticated }
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension AsyncSmtpSession: AsyncMessageTransport {
    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws {
        _ = try await sendMail(from: from, to: recipients, data: data)
    }
}
