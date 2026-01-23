//
// SmtpSession.swift
//
// Higher-level synchronous SMTP session helpers.
//

public final class SmtpSession {
    private let client: SmtpClient
    private let transport: Transport
    private let maxReads: Int

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.transport = transport
        self.client = SmtpClient(protocolLogger: protocolLogger)
        self.maxReads = maxReads
    }

    @discardableResult
    public func connect() throws -> SmtpResponse {
        client.connect(transport: transport)
        guard let greeting = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        return greeting
    }

    public func disconnect() {
        _ = client.send(.quit)
        transport.close()
    }

    public func ehlo(domain: String) throws -> SmtpCapabilities {
        _ = client.send(.ehlo(domain))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if let capabilities = client.handleEhloResponse(response) {
            return capabilities
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func helo(domain: String) throws -> SmtpResponse {
        _ = client.send(.helo(domain))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func authenticate(mechanism: String, initialResponse: String? = nil) throws -> SmtpResponse {
        _ = client.send(.auth(mechanism, initialResponse: initialResponse))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func sendMail(from: String, to recipients: [String], data: [UInt8]) throws -> SmtpResponse {
        _ = client.send(.mailFrom(from))
        try ensureWrite()
        guard let mailResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            _ = client.send(.rcptTo(recipient))
            try ensureWrite()
            guard let rcptResponse = client.waitForResponse(maxReads: maxReads) else {
                throw SessionError.timeout
            }
            guard rcptResponse.isSuccess else {
                throw SessionError.smtpError(code: rcptResponse.code, message: rcptResponse.lines.joined(separator: " "))
            }
        }

        if let dataResponse = client.sendData(data, maxReads: maxReads) {
            try ensureWrite()
            if dataResponse.isSuccess {
                return dataResponse
            }
            throw SessionError.smtpError(code: dataResponse.code, message: dataResponse.lines.joined(separator: " "))
        }
        throw SessionError.timeout
    }

    public func startTls(validateCertificate: Bool = true) throws -> SmtpResponse {
        guard let tlsTransport = transport as? StartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        _ = client.send(.starttls)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isSuccess else {
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }
        tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }
}
