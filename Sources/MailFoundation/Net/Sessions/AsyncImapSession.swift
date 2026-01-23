//
// AsyncImapSession.swift
//
// Higher-level async IMAP session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapSession {
    private let client: AsyncImapClient
    private let transport: AsyncTransport

    public init(transport: AsyncTransport) {
        self.transport = transport
        self.client = AsyncImapClient(transport: transport)
    }

    public static func make(host: String, port: UInt16, backend: AsyncTransportBackend = .network) throws -> AsyncImapSession {
        let transport = try AsyncTransportFactory.make(host: host, port: port, backend: backend)
        return AsyncImapSession(transport: transport)
    }

    @discardableResult
    public func connect() async throws -> ImapResponse? {
        try await client.start()
        return await waitForGreeting()
    }

    public func disconnect() async {
        _ = try? await client.logout()
        await client.stop()
    }

    public func capability() async throws -> ImapResponse? {
        try await client.capability()
    }

    public func login(user: String, password: String) async throws -> ImapResponse? {
        try await client.login(user: user, password: password)
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        try await client.select(mailbox: mailbox)
    }

    public func close() async throws -> ImapResponse? {
        try await client.close()
    }

    public func state() async -> AsyncImapClient.State {
        await client.state
    }

    public func capabilities() async -> ImapCapabilities? {
        await client.capabilities
    }

    public func search(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        let command = try await client.send(.search(criteria))
        var ids: [UInt32] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let search = ImapSearchResponse.parse(message.line) {
                    ids = search.ids
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        return ImapSearchResponse(ids: ids)
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func status(mailbox: String, items: [String], maxEmptyReads: Int = 10) async throws -> ImapStatusResponse {
        let command = try await client.send(.status(mailbox, items: items))
        var result: ImapStatusResponse?
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let status = ImapStatusResponse.parse(message.line) {
                    result = status
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk, let result {
                        return result
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetch(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let command = try await client.send(.fetch(set, items))
        var results: [ImapFetchResponse] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        return results
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchAttributes(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchAttributes] {
        let responses = try await fetch(set, items: items, maxEmptyReads: maxEmptyReads)
        return responses.compactMap(ImapFetchAttributes.parse)
    }

    public func startTls(validateCertificate: Bool = true, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        guard let tlsTransport = transport as? AsyncStartTlsTransport else {
            throw SessionError.startTlsNotSupported
        }
        let command = try await client.send(.starttls)
        var emptyReads = 0
        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    try await tlsTransport.startTLS(validateCertificate: validateCertificate)
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func startIdle(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        let command = try await client.send(.idle)
        var emptyReads = 0
        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let response = message.response, case .continuation = response.kind {
                    return response
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }
        throw SessionError.timeout
    }

    public func readIdleEvents(maxEmptyReads: Int = 10) async throws -> [ImapIdleEvent] {
        var emptyReads = 0
        var events: [ImapIdleEvent] = []
        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let event = ImapIdleEvent.parse(message.line) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                return events
            }
        }
        throw SessionError.timeout
    }

    public func stopIdle() async throws {
        _ = try await client.send(.idleDone)
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxEmptyReads: Int = 10) async throws -> [ImapQresyncEvent] {
        var emptyReads = 0
        var events: [ImapQresyncEvent] = []
        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let event = ImapQresyncEvent.parse(message, validity: validity) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                return events
            }
        }
        throw SessionError.timeout
    }

    private func waitForGreeting() async -> ImapResponse? {
        while true {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                return nil
            }
            for message in messages {
                if let response = message.response {
                    return response
                }
            }
        }
    }
}
