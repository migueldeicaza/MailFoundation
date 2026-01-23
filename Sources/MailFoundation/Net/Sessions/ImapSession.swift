//
// ImapSession.swift
//
// Higher-level synchronous IMAP session helpers.
//

public final class ImapSession {
    private let client: ImapClient
    private let transport: Transport
    private let maxReads: Int

    public init(transport: Transport, protocolLogger: ProtocolLoggerType = NullProtocolLogger(), maxReads: Int = 10) {
        self.transport = transport
        self.client = ImapClient(protocolLogger: protocolLogger)
        self.maxReads = maxReads
    }

    @discardableResult
    public func connect() throws -> ImapResponse {
        client.connect(transport: transport)
        guard let greeting = waitForGreeting() else {
            throw SessionError.timeout
        }
        if greeting.status == .ok || greeting.status == .preauth {
            return greeting
        }
        throw SessionError.imapError(status: greeting.status, text: greeting.text)
    }

    public func disconnect() {
        _ = client.send(.logout)
        transport.close()
    }

    public func capability() throws -> ImapResponse {
        let command = client.send(.capability)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func login(user: String, password: String) throws -> ImapResponse {
        let command = client.send(.login(user, password))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func select(mailbox: String) throws -> ImapResponse {
        let command = client.send(.select(mailbox))
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        return response
    }

    public func search(_ criteria: String) throws -> ImapSearchResponse {
        let command = client.send(.search(criteria))
        try ensureWrite()
        var ids: [UInt32] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let line = message.line as String? {
                    if let search = ImapSearchResponse.parse(line) {
                        ids = search.ids
                    }
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapSearchResponse(ids: ids)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetch(_ set: String, items: String) throws -> [ImapFetchResponse] {
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return results
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchAttributes(_ set: String, items: String) throws -> [ImapFetchAttributes] {
        let responses = try fetch(set, items: items)
        return responses.compactMap(ImapFetchAttributes.parse)
    }

    public func status(mailbox: String, items: [String]) throws -> ImapStatusResponse {
        let command = client.send(.status(mailbox, items: items))
        try ensureWrite()
        var result: ImapStatusResponse?
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let status = ImapStatusResponse.parse(message.line) {
                    result = status
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    if let result {
                        return result
                    }
                    throw SessionError.imapError(status: response.status, text: "STATUS response missing")
                }
            }
        }

        throw SessionError.timeout
    }

    public func startTls(validateCertificate: Bool = true) throws -> ImapResponse {
        guard let tlsTransport = transport as? StartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        let command = client.send(.starttls)
        try ensureWrite()
        guard let response = client.waitForTagged(command.tag, maxReads: maxReads) else {
            throw SessionError.timeout
        }
        guard response.isOk else {
            throw SessionError.imapError(status: response.status, text: response.text)
        }
        tlsTransport.startTLS(validateCertificate: validateCertificate)
        return response
    }

    public func startIdle() throws -> ImapResponse {
        _ = client.send(.idle)
        try ensureWrite()
        guard let response = client.waitForContinuation(maxReads: maxReads) else {
            throw SessionError.timeout
        }
        return response
    }

    public func readIdleEvents(maxReads: Int? = nil) -> [ImapIdleEvent] {
        let limit = maxReads ?? self.maxReads
        var reads = 0
        var events: [ImapIdleEvent] = []
        while reads < limit {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let event = ImapIdleEvent.parse(message.line) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                break
            }
        }
        return events
    }

    private func waitForGreeting() -> ImapResponse? {
        var reads = 0
        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let response = message.response {
                    return response
                }
            }
        }
        return nil
    }

    private func ensureWrite() throws {
        if !client.lastWriteSucceeded {
            throw SessionError.transportWriteFailed
        }
    }
}
