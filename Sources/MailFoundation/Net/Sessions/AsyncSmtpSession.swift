//
// AsyncSmtpSession.swift
//
// Higher-level async SMTP session helpers.
//

/// Default timeout for SMTP operations in milliseconds (2 minutes, matching MailKit).
public let defaultSmtpTimeoutMs = 120_000

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpSession {
    private let client: AsyncSmtpClient
    private let transport: AsyncTransport

    /// The timeout for network operations in milliseconds.
    ///
    /// Default is 120000 (2 minutes), matching MailKit's default.
    /// Set to `Int.max` for no timeout.
    public private(set) var timeoutMilliseconds: Int = defaultSmtpTimeoutMs

    /// Sets the timeout for network operations.
    ///
    /// - Parameter milliseconds: The timeout in milliseconds
    public func setTimeoutMilliseconds(_ milliseconds: Int) {
        timeoutMilliseconds = milliseconds
    }

    public init(transport: AsyncTransport, timeoutMilliseconds: Int = defaultSmtpTimeoutMs) {
        self.transport = transport
        self.client = AsyncSmtpClient(transport: transport)
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        timeoutMilliseconds: Int = defaultSmtpTimeoutMs
    ) throws -> AsyncSmtpSession {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncSmtpSession(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network,
        proxy: ProxySettings,
        timeoutMilliseconds: Int = defaultSmtpTimeoutMs
    ) async throws -> AsyncSmtpSession {
        let transport = try await AsyncTransportFactory.make(host: host, port: port, backend: backend, proxy: proxy)
        return AsyncSmtpSession(transport: transport, timeoutMilliseconds: timeoutMilliseconds)
    }

    @discardableResult
    public func connect() async throws -> SmtpResponse? {
        try await withSessionTimeout {
            try await self.client.start()
            return await self.client.waitForResponse()
        }
    }

    public func disconnect() async {
        _ = try? await withSessionTimeout {
            _ = try await self.client.send(.quit)
        }
        await client.stop()
    }

    public func ehlo(domain: String) async throws -> SmtpCapabilities? {
        try await withSessionTimeout {
            try await self.client.ehlo(domain: domain)
        }
    }

    public func helo(domain: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.helo(domain))
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func noop() async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.noop)
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func rset() async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.rset)
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func vrfy(_ argument: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.vrfy(argument))
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func vrfyResult(_ argument: String) async throws -> SmtpVrfyResult {
        guard let response = try await vrfy(argument) else {
            throw SessionError.timeout
        }
        return SmtpVrfyResult(response: response)
    }

    public func expn(_ argument: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.expn(argument))
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func expnResult(_ argument: String) async throws -> SmtpExpnResult {
        guard let response = try await expn(argument) else {
            throw SessionError.timeout
        }
        return SmtpExpnResult(response: response)
    }

    public func help(_ argument: String? = nil) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.help(argument))
            return try self.requireSuccess(await self.client.waitForResponse())
        }
    }

    public func helpResult(_ argument: String? = nil) async throws -> SmtpHelpResult {
        guard let response = try await help(argument) else {
            throw SessionError.timeout
        }
        return SmtpHelpResult(response: response)
    }

    private nonisolated func requireSuccess(_ response: SmtpResponse?) throws -> SmtpResponse {
        guard let response else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw self.smtpCommandError(.unexpectedStatusCode, response: response)
        }
        return response
    }

    public func mailFrom(_ address: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.mailFrom(address))
            return await self.client.waitForResponse()
        }
    }

    public func mailFrom(_ address: String, parameters: SmtpMailFromParameters) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.mailFromParameters(address, parameters))
            return await self.client.waitForResponse()
        }
    }

    public func rcptTo(_ address: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.rcptTo(address))
            return await self.client.waitForResponse()
        }
    }

    public func rcptTo(_ address: String, parameters: SmtpRcptToParameters) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.rcptToParameters(address, parameters))
            return await self.client.waitForResponse()
        }
    }

    public func data(_ message: [UInt8]) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            try await self.client.sendData(message)
        }
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            try await self.client.authenticate(mechanism: mechanism, initialResponse: initialResponse)
        }
    }

    public func authenticate(_ authentication: SmtpAuthentication) async throws -> SmtpResponse? {
        if let responder = authentication.responder {
            let response = try await authenticate(
                mechanism: authentication.mechanism,
                initialResponse: authentication.initialResponse,
                responder: { challenge in
                    try responder(challenge)
                }
            )
            return response
        }
        return try await authenticate(
            mechanism: authentication.mechanism,
            initialResponse: authentication.initialResponse
        )
    }

    public func authenticate(
        mechanism: String,
        initialResponse: String? = nil,
        responder: @Sendable @escaping (String) async throws -> String
    ) async throws -> SmtpResponse {
        try await withSessionTimeout {
            _ = try await self.client.send(.auth(mechanism, initialResponse: initialResponse))
            guard var response = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }

            while response.code == 334 {
                try Task.checkCancellation()
                let challenge = response.lines.first ?? ""
                let reply = try await responder(challenge)
                _ = try await self.client.sendLine(reply)
                guard let next = await self.client.waitForResponse() else {
                    throw SessionError.timeout
                }
                response = next
            }

            if response.isSuccess {
                return response
            }
            throw self.smtpCommandError(.unexpectedStatusCode, response: response)
        }
    }

    public func sendData(_ message: [UInt8]) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            try await self.client.sendData(message)
        }
    }

    public func sendMail(from: String, to recipients: [String], data: [UInt8]) async throws -> SmtpResponse {
        try await withSessionTimeout {
            _ = try await self.client.send(.mailFrom(from))
            guard let mailResponse = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard mailResponse.isSuccess else {
                throw self.smtpCommandError(.senderNotAccepted, response: mailResponse, mailboxAddress: from)
            }

            for recipient in recipients {
                try Task.checkCancellation()
                _ = try await self.client.send(.rcptTo(recipient))
                guard let rcptResponse = await self.client.waitForResponse() else {
                    throw SessionError.timeout
                }
                guard rcptResponse.isSuccess else {
                    throw self.smtpCommandError(.recipientNotAccepted, response: rcptResponse, mailboxAddress: recipient)
                }
            }

            if let response = try await self.client.sendData(data) {
                if response.isSuccess {
                    return response
                }
                throw self.smtpCommandError(.messageNotAccepted, response: response)
            }

            throw SessionError.timeout
        }
    }

    public func sendMail(
        from: String,
        to recipients: [String],
        data: [UInt8],
        mailParameters: SmtpMailFromParameters?,
        rcptParameters: SmtpRcptToParameters?
    ) async throws -> SmtpResponse {
        try await withSessionTimeout {
            if let mailParameters {
                _ = try await self.client.send(.mailFromParameters(from, mailParameters))
            } else {
                _ = try await self.client.send(.mailFrom(from))
            }
            guard let mailResponse = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard mailResponse.isSuccess else {
                throw self.smtpCommandError(.senderNotAccepted, response: mailResponse, mailboxAddress: from)
            }

            for recipient in recipients {
                try Task.checkCancellation()
                if let rcptParameters {
                    _ = try await self.client.send(.rcptToParameters(recipient, rcptParameters))
                } else {
                    _ = try await self.client.send(.rcptTo(recipient))
                }
                guard let rcptResponse = await self.client.waitForResponse() else {
                    throw SessionError.timeout
                }
                guard rcptResponse.isSuccess else {
                    throw self.smtpCommandError(.recipientNotAccepted, response: rcptResponse, mailboxAddress: recipient)
                }
            }

            if let response = try await self.client.sendData(data) {
                if response.isSuccess {
                    return response
                }
                throw self.smtpCommandError(.messageNotAccepted, response: response)
            }

            throw SessionError.timeout
        }
    }

    public func sendMailPipelined(
        from: String,
        to recipients: [String],
        data: [UInt8],
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        try await withSessionTimeout {
            if let mailParameters {
                _ = try await self.client.send(.mailFromParameters(from, mailParameters))
            } else {
                _ = try await self.client.send(.mailFrom(from))
            }

            for recipient in recipients {
                if let rcptParameters {
                    _ = try await self.client.send(.rcptToParameters(recipient, rcptParameters))
                } else {
                    _ = try await self.client.send(.rcptTo(recipient))
                }
            }

            guard let mailResponse = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard mailResponse.isSuccess else {
                throw self.smtpCommandError(.senderNotAccepted, response: mailResponse, mailboxAddress: from)
            }

            for recipient in recipients {
                guard let rcptResponse = await self.client.waitForResponse() else {
                    throw SessionError.timeout
                }
                guard rcptResponse.isSuccess else {
                    throw self.smtpCommandError(.recipientNotAccepted, response: rcptResponse, mailboxAddress: recipient)
                }
            }

            if let dataResponse = try await self.client.sendData(data) {
                if dataResponse.isSuccess {
                    return dataResponse
                }
                throw self.smtpCommandError(.messageNotAccepted, response: dataResponse)
            }

            throw SessionError.timeout
        }
    }

    public func sendBdat(_ data: [UInt8], last: Bool) async throws -> SmtpResponse {
        try await withSessionTimeout {
            _ = try await self.client.send(.bdat(data.count, last: last))
            _ = try await self.client.sendRaw(data)
            guard let response = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard response.isSuccess else {
                throw self.smtpCommandError(.messageNotAccepted, response: response)
            }
            return response
        }
    }

    public func sendMailChunked(
        from: String,
        to recipients: [String],
        data: [UInt8],
        chunkSize: Int = 4096,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        try await withSessionTimeout {
            let size = max(1, chunkSize)
            if let mailParameters {
                _ = try await self.client.send(.mailFromParameters(from, mailParameters))
            } else {
                _ = try await self.client.send(.mailFrom(from))
            }
            guard let mailResponse = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard mailResponse.isSuccess else {
                throw self.smtpCommandError(.senderNotAccepted, response: mailResponse, mailboxAddress: from)
            }

            for recipient in recipients {
                try Task.checkCancellation()
                if let rcptParameters {
                    _ = try await self.client.send(.rcptToParameters(recipient, rcptParameters))
                } else {
                    _ = try await self.client.send(.rcptTo(recipient))
                }
                guard let rcptResponse = await self.client.waitForResponse() else {
                    throw SessionError.timeout
                }
                guard rcptResponse.isSuccess else {
                    throw self.smtpCommandError(.recipientNotAccepted, response: rcptResponse, mailboxAddress: recipient)
                }
            }

            var response = mailResponse
            if !data.isEmpty {
                var offset = 0
                while offset < data.count {
                    try Task.checkCancellation()
                    let end = min(offset + size, data.count)
                    let chunk = Array(data[offset..<end])
                    let isLast = end == data.count
                    response = try await self.sendBdat(chunk, last: isLast)
                    offset = end
                }
            }
            return response
        }
    }

    public func startTls(validateCertificate: Bool = true) async throws -> SmtpResponse {
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        return try await withSessionTimeout {
            _ = try await self.client.send(.starttls)
            guard let response = await self.client.waitForResponse() else {
                throw SessionError.timeout
            }
            guard response.isSuccess else {
                throw self.smtpCommandError(.unexpectedStatusCode, response: response)
            }
            try await tlsTransport.startTLS(validateCertificate: validateCertificate)
            return response
        }
    }

    public func etrn(_ argument: String) async throws -> SmtpResponse? {
        try await withSessionTimeout {
            _ = try await self.client.send(.etrn(argument))
            return await self.client.waitForResponse()
        }
    }

    private func withSessionTimeout<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withTimeout(milliseconds: timeoutMilliseconds, operation: operation)
    }

    public func capabilities() async -> SmtpCapabilities? {
        await client.capabilities
    }

    private nonisolated func smtpError(from response: SmtpResponse) -> SessionError {
        SessionError.smtpError(
            code: response.code,
            message: response.lines.joined(separator: " "),
            enhancedStatusCode: response.enhancedStatusCode
        )
    }

    private nonisolated func smtpCommandError(
        _ code: SmtpErrorCode,
        response: SmtpResponse,
        mailboxAddress: String? = nil
    ) -> SmtpCommandError {
        SmtpCommandError(errorCode: code, response: response, mailboxAddress: mailboxAddress)
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
