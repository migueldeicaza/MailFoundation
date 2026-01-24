//
// SmtpTransport.swift
//
// MailTransport-based SMTP wrapper.
//

import SwiftMimeKit

public final class SmtpTransport: MailTransportBase<SmtpResponse>, MailTransport {
    private let session: SmtpSession
    private var storedCapabilities: SmtpCapabilities?

    public static func make(
        host: String,
        port: Int,
        backend: TransportBackend = .tcp,
        protocolLogger: ProtocolLoggerType = NullProtocolLogger(),
        maxReads: Int = 10
    ) throws -> SmtpTransport {
        let transport = try TransportFactory.make(host: host, port: port, backend: backend)
        return SmtpTransport(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
    }

    public init(
        transport: Transport,
        protocolLogger: ProtocolLoggerType = NullProtocolLogger(),
        maxReads: Int = 10
    ) {
        self.session = SmtpSession(transport: transport, protocolLogger: protocolLogger, maxReads: maxReads)
        super.init(protocolLogger: protocolLogger)
    }

    public override var protocolLogger: ProtocolLoggerType {
        didSet {
            session.protocolLogger = protocolLogger
        }
    }

    public override var protocolName: String { "SMTP" }

    public var capabilities: SmtpCapabilities? { storedCapabilities }

    @discardableResult
    public override func connect() throws -> SmtpResponse {
        let response = try session.connect()
        updateState(.connected)
        return response
    }

    public override func disconnect() {
        session.disconnect()
        updateState(.disconnected)
    }

    public func ehlo(domain: String) throws -> SmtpCapabilities {
        let capabilities = try session.ehlo(domain: domain)
        storedCapabilities = capabilities
        updateAuthenticationMechanisms(from: capabilities)
        return capabilities
    }

    public func helo(domain: String) throws -> SmtpResponse {
        try session.helo(domain: domain)
    }

    public func noop() throws -> SmtpResponse {
        try session.noop()
    }

    public func rset() throws -> SmtpResponse {
        try session.rset()
    }

    public func vrfy(_ argument: String) throws -> SmtpResponse {
        try session.vrfy(argument)
    }

    public func vrfyResult(_ argument: String) throws -> SmtpVrfyResult {
        try session.vrfyResult(argument)
    }

    public func expn(_ argument: String) throws -> SmtpResponse {
        try session.expn(argument)
    }

    public func expnResult(_ argument: String) throws -> SmtpExpnResult {
        try session.expnResult(argument)
    }

    public func help(_ argument: String? = nil) throws -> SmtpResponse {
        try session.help(argument)
    }

    public func helpResult(_ argument: String? = nil) throws -> SmtpHelpResult {
        try session.helpResult(argument)
    }

    public func startTls(validateCertificate: Bool = true) throws -> SmtpResponse {
        let response = try session.startTls(validateCertificate: validateCertificate)
        storedCapabilities = nil
        updateAuthenticationMechanisms([])
        updateState(.connected)
        return response
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) throws -> SmtpResponse {
        let response = try session.authenticate(mechanism: mechanism, initialResponse: initialResponse)
        updateState(.authenticated)
        return response
    }

    public func send(
        _ message: MimeMessage,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) throws -> SmtpResponse {
        try ensureConnected()
        try ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let mailParameters = resolveMailParameters(nil, data: envelope.data, options: options)
        let response = try session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data,
            mailParameters: mailParameters,
            rcptParameters: nil
        )
        notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func send(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) throws -> SmtpResponse {
        try ensureConnected()
        try ensureInternationalSupport(options)
        let data = try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
        let mailParameters = resolveMailParameters(nil, data: data, options: options)
        let response = try session.sendMail(
            from: sender.address,
            to: recipients.map { $0.address },
            data: data,
            mailParameters: mailParameters,
            rcptParameters: nil
        )
        notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendChunked(
        _ message: MimeMessage,
        chunkSize: Int = 4096,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) throws -> SmtpResponse {
        try ensureConnected()
        try ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let resolvedMailParameters = resolveMailParameters(mailParameters, data: envelope.data, options: options)
        let response: SmtpResponse
        if supportsCapability("CHUNKING") {
            response = try session.sendMailChunked(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                chunkSize: chunkSize,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
        } else {
            response = try session.sendMail(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
        }
        notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendPipelined(
        _ message: MimeMessage,
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil,
        mailParameters: SmtpMailFromParameters? = nil,
        rcptParameters: SmtpRcptToParameters? = nil
    ) throws -> SmtpResponse {
        try ensureConnected()
        try ensureInternationalSupport(options)
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let resolvedMailParameters = resolveMailParameters(mailParameters, data: envelope.data, options: options)
        let response: SmtpResponse
        if supportsCapability("PIPELINING") {
            response = try session.sendMailPipelined(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
        } else {
            response = try session.sendMail(
                from: envelope.sender.address,
                to: envelope.recipients.map { $0.address },
                data: envelope.data,
                mailParameters: resolvedMailParameters,
                rcptParameters: rcptParameters
            )
        }
        notifyMessageSent(message: message, response: response.lines.joined(separator: " "))
        return response
    }

    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) throws {
        try ensureConnected()
        let mailParameters = resolveMailParameters(nil, data: data, options: MailTransportFormatOptions.default)
        _ = try session.sendMail(
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
    ) throws {
        _ = try send(message, options: options, progress: progress)
    }

    public func sendMessage(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = MailTransportFormatOptions.default,
        progress: TransferProgress? = nil
    ) throws {
        _ = try send(message, sender: sender, recipients: recipients, options: options, progress: progress)
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

        if mechanisms.isEmpty {
            updateAuthenticationMechanisms([])
        } else {
            updateAuthenticationMechanisms(mechanisms)
        }
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

    private func ensureConnected() throws {
        guard isConnected else {
            throw MailTransportError.notConnected
        }
    }

    private func ensureInternationalSupport(_ options: FormatOptions) throws {
        if options.international, !supportsCapability("SMTPUTF8") {
            throw MailTransportError.internationalNotSupported
        }
    }
}
