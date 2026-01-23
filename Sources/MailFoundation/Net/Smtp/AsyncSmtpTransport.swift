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
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) async throws -> SmtpResponse {
        let envelope = try MailTransportEnvelopeBuilder.build(for: message, options: options, progress: progress)
        return try await session.sendMail(
            from: envelope.sender.address,
            to: envelope.recipients.map { $0.address },
            data: envelope.data
        )
    }

    public func send(
        _ message: MimeMessage,
        sender: MailboxAddress,
        recipients: [MailboxAddress],
        options: FormatOptions = .default,
        progress: TransferProgress? = nil
    ) async throws -> SmtpResponse {
        let data = try MailTransportEnvelopeBuilder.encodeMessage(message, options: options, progress: progress)
        return try await session.sendMail(
            from: sender.address,
            to: recipients.map { $0.address },
            data: data
        )
    }

    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws {
        _ = try await session.sendMail(from: from, to: recipients, data: data)
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
}
