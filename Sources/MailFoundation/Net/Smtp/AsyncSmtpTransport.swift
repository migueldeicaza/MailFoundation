//
// AsyncSmtpTransport.swift
//
// Async SMTP transport wrapper.
//

import SwiftMimeKit

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncSmtpTransport: AsyncMailTransport {
    public typealias ConnectResponse = SmtpResponse?
    private let session: AsyncSmtpSession
    private var storedCapabilities: SmtpCapabilities?
    private var authenticationMechanisms: Set<String> = []
    public typealias MessageSentHandler = @Sendable (MessageSentEvent) async -> Void
    private var messageSentHandlers: [MessageSentHandler] = []

    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend = .network
    ) throws -> AsyncSmtpTransport {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncSmtpTransport(transport: transport)
    }

    public init(transport: AsyncTransport) {
        self.session = AsyncSmtpSession(transport: transport)
    }

    public var capabilities: SmtpCapabilities? { storedCapabilities }

    public var authMechanisms: Set<String> { authenticationMechanisms }

    public var state: MailServiceState {
        get async { await session.state }
    }

    public var isConnected: Bool {
        get async { await session.isConnected }
    }

    public var isAuthenticated: Bool {
        get async { await session.isAuthenticated }
    }

    @discardableResult
    public func connect() async throws -> SmtpResponse? {
        try await session.connect()
    }

    public func disconnect() async {
        await session.disconnect()
    }

    public func addMessageSentHandler(_ handler: @escaping MessageSentHandler) async {
        messageSentHandlers.append(handler)
    }

    public func removeAllMessageSentHandlers() async {
        messageSentHandlers.removeAll()
    }

    public func ehlo(domain: String) async throws -> SmtpCapabilities? {
        let capabilities = try await session.ehlo(domain: domain)
        if let capabilities {
            storedCapabilities = capabilities
            updateAuthenticationMechanisms(from: capabilities)
        }
        return capabilities
    }

    public func helo(domain: String) async throws -> SmtpResponse? {
        try await session.helo(domain: domain)
    }

    public func noop() async throws -> SmtpResponse? {
        try await session.noop()
    }

    public func rset() async throws -> SmtpResponse? {
        try await session.rset()
    }

    public func startTls(validateCertificate: Bool = true) async throws -> SmtpResponse {
        let response = try await session.startTls(validateCertificate: validateCertificate)
        storedCapabilities = nil
        authenticationMechanisms.removeAll()
        return response
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) async throws -> SmtpResponse? {
        try await session.authenticate(mechanism: mechanism, initialResponse: initialResponse)
    }

    public func send(
        _ message: MimeMessage,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) async throws -> SmtpResponse {
        try await ensureConnected()
        try await ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let mailParameters = resolveMailParameters(nil, data: envelope.data, options: options)
        let response = try await session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data,
            mailParameters: mailParameters,
            rcptParameters: nil
        )
        await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func send(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) async throws -> SmtpResponse {
        try await ensureConnected()
        try await ensureInternationalSupport(options)
        let data = try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
        let mailParameters = resolveMailParameters(nil, data: data, options: options)
        let response = try await session.sendMail(
            from: sender.address,
            to: recipients.map { $0.address },
            data: data,
            mailParameters: mailParameters,
            rcptParameters: nil
        )
        await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendChunked(
        _ message: MimeMessage,
        chunkSize: Int = 4096,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        try await ensureConnected()
        try await ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let resolvedMailParameters = resolveMailParameters(mailParameters, data: envelope.data, options: options)
        if supportsCapability("CHUNKING") {
            let response = try await session.sendMailChunked(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                chunkSize: chunkSize,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
            await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
            return response
        }
        let response = try await session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data,
            mailParameters: resolvedMailParameters,
            rcptParameters: rcptParameters
        )
        await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendPipelined(
        _ message: MimeMessage,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) async throws -> SmtpResponse {
        try await ensureConnected()
        try await ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let resolvedMailParameters = resolveMailParameters(mailParameters, data: envelope.data, options: options)
        if supportsCapability("PIPELINING") {
            let response = try await session.sendMailPipelined(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
            await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
            return response
        }
        let response = try await session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data,
            mailParameters: resolvedMailParameters,
            rcptParameters: rcptParameters
        )
        await notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws {
        try await ensureConnected()
        let mailParameters = resolveMailParameters(nil, data: data, options: MailTransportFormatOptions.default)
        _ = try await session.sendMail(
            from: from,
            to: recipients,
            data: data,
            mailParameters: mailParameters,
            rcptParameters: nil
        )
    }

    public func sendMessage(
        _ message: MimeMessage,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) async throws {
        _ = try await send(message, options: options, progress: progress)
    }

    public func sendMessage(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) async throws {
        _ = try await send(message, sender: sender, recipients: recipients, options: options, progress: progress)
    }

    private func updateAuthenticationMechanisms(from capabilities: SmtpCapabilities) {
        var mechanisms: [String] = []

        if let authValue = capabilities.value(for: "AUTH") {
            mechanisms.append(contentsOf: authValue.split(whereSeparator: { $0 == " " }).map(String.init))
        }

        for flag in capabilities.flags where flag.hasPrefix("AUTH=") {
            let value = String(flag.dropFirst("AUTH=".count))
            if !value.isEmpty {
                mechanisms.append(contentsOf: value.split(whereSeparator: { $0 == " " }).map(String.init))
            }
        }

        authenticationMechanisms = Set(mechanisms.map { $0.uppercased() })
    }

    private func supportsCapability(_ name: String) -> Bool {
        storedCapabilities?.supports(name) ?? false
    }

    private func resolveMailParameters(
        _ base: SmtpMailFromParameters?,
        data: [UInt8],
        options: FormatOptions
    ) -> SmtpMailFromParameters? {
        var parameters = base ?? SmtpMailFromParameters()
        var hasParameters = base != nil

        if options.international {
            parameters.smtpUtf8 = true
            hasParameters = true
        }

        if supportsCapability("SIZE"), parameters.size == nil {
            parameters.size = data.count
            hasParameters = true
        }

        if supportsCapability("8BITMIME"), parameters.body == nil, dataContainsNonAscii(data) {
            parameters.body = .eightBitMime
            hasParameters = true
        }

        return hasParameters ? parameters : nil
    }

    private func dataContainsNonAscii(_ data: [UInt8]) -> Bool {
        data.contains { $0 > 0x7f }
    }

    private func ensureConnected() async throws {
        guard await session.isConnected else {
            throw MailTransportError.notConnected
        }
    }

    private func ensureInternationalSupport(_ options: FormatOptions) async throws {
        if options.international, !supportsCapability("SMTPUTF8") {
            throw MailTransportError.internationalNotSupported
        }
    }

    private func notifyMessageSent(message: MimeMessage, response: String) async {
        guard !messageSentHandlers.isEmpty else { return }
        let event = MessageSentEvent(message: message, response: response)
        for handler in messageSentHandlers {
            await handler(event)
        }
    }
}
