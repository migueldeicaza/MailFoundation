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
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> SmtpResponse {
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        let response = try session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data
        )
        notifyMessageSent(response: response.lines.joined(separator: " "))
        return response
    }

    public func send(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) throws -> SmtpResponse {
        let data = try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
        let response = try session.sendMail(
            from: sender.address,
            to: recipients.map { $0.address },
            data: data
        )
        notifyMessageSent(response: response.lines.joined(separator: " "))
        return response
    }

    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) throws {
        _ = try session.sendMail(from: from, to: recipients, data: data)
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
}
