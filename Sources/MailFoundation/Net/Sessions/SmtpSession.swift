//
// SmtpSession.swift
//
// Higher-level synchronous SMTP session helpers.
//

public final class SmtpSession {
    private let client: SmtpClient
    private let transport: Transport
    private let maxReads: Int
    
    public var protocolLogger: ProtocolLoggerType {
        get { client.protocolLogger }
        set { client.protocolLogger = newValue }
    }

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

    public func noop() throws -> SmtpResponse {
        _ = client.send(.noop)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func rset() throws -> SmtpResponse {
        _ = client.send(.rset)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func vrfy(_ argument: String) throws -> SmtpResponse {
        _ = client.send(.vrfy(argument))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func expn(_ argument: String) throws -> SmtpResponse {
        _ = client.send(.expn(argument))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func help(_ argument: String? = nil) throws -> SmtpResponse {
        _ = client.send(.help(argument))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func mailFrom(_ address: String) throws -> SmtpResponse {
        _ = client.send(.mailFrom(address))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func mailFrom(_ address: String, parameters: SmtpMailFromParameters) throws -> SmtpResponse {
        _ = client.send(.mailFromParameters(address, parameters))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func rcptTo(_ address: String) throws -> SmtpResponse {
        _ = client.send(.rcptTo(address))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func rcptTo(_ address: String, parameters: SmtpRcptToParameters) throws -> SmtpResponse {
        _ = client.send(.rcptToParameters(address, parameters))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    public func sendData(_ message: [UInt8]) throws -> SmtpResponse {
        if let response = client.sendData(message, maxReads: maxReads) {
            try ensureWrite()
            if response.isSuccess {
                return response
            }
            throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
        }
        throw SessionError.timeout
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

    public func authenticate(
        mechanism: String,
        initialResponse: String? = nil,
        responder: (String) throws -> String
    ) throws -> SmtpResponse {
        _ = client.send(.auth(mechanism, initialResponse: initialResponse))
        try ensureWrite()
        guard var response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }

        while response.code == 334 {
            let challenge = response.lines.first ?? ""
            let reply = try responder(challenge)
            _ = client.sendLine(reply)
            try ensureWrite()
            guard let next = client.waitForResponse(maxReads: maxReads) else {
                throw SessionError.timeout
            }
            response = next
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

    public func sendMail(
        from: String,
        to recipients: [String],
        data: [UInt8],
        mailParameters: SmtpMailFromParameters?,
        rcptParameters: SmtpRcptToParameters?
    ) throws -> SmtpResponse {
        if let mailParameters {
            _ = client.send(.mailFromParameters(from, mailParameters))
        } else {
            _ = client.send(.mailFrom(from))
        }
        try ensureWrite()
        guard let mailResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            if let rcptParameters {
                _ = client.send(.rcptToParameters(recipient, rcptParameters))
            } else {
                _ = client.send(.rcptTo(recipient))
            }
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

    public func sendBdat(_ data: [UInt8], last: Bool) throws -> SmtpResponse {
        _ = client.send(.bdat(data.count, last: last))
        try ensureWrite()
        _ = client.sendRaw(data)
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
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
    ) throws -> SmtpResponse {
        let size = max(1, chunkSize)
        if let mailParameters {
            _ = client.send(.mailFromParameters(from, mailParameters))
        } else {
            _ = client.send(.mailFrom(from))
        }
        try ensureWrite()
        guard let mailResponse = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard mailResponse.isSuccess else {
            throw SessionError.smtpError(code: mailResponse.code, message: mailResponse.lines.joined(separator: " "))
        }

        for recipient in recipients {
            if let rcptParameters {
                _ = client.send(.rcptToParameters(recipient, rcptParameters))
            } else {
                _ = client.send(.rcptTo(recipient))
            }
            try ensureWrite()
            guard let rcptResponse = client.waitForResponse(maxReads: maxReads) else {
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
                response = try sendBdat(chunk, last: isLast)
                offset = end
            }
        }
        return response
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

    public func etrn(_ argument: String) throws -> SmtpResponse {
        _ = client.send(.etrn(argument))
        try ensureWrite()
        guard let response = client.waitForResponse(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        if response.isSuccess {
            return response
        }
        throw SessionError.smtpError(code: response.code, message: response.lines.joined(separator: " "))
    }

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }
}

extension SmtpSession: MailService {
    public typealias ConnectResponse = SmtpResponse

    public var state: MailServiceState {
        switch client.state {
        case .disconnected:
            return .disconnected
        case .connected:
            return client.isAuthenticated ? .authenticated : .connected
        case .authenticating:
            return .connected
        }
    }

    public var isConnected: Bool { client.isConnected }

    public var isAuthenticated: Bool { client.isAuthenticated }
}

extension SmtpSession: MessageTransport {
    public func sendMessage(from: String, to recipients: [String], data: [UInt8]) throws {
        _ = try sendMail(from: from, to: recipients, data: data)
    }
}
