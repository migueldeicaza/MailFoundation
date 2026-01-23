//
// AsyncImapSession.swift
//
// Higher-level async IMAP session helpers.
//

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncImapSession {
    private let client: AsyncImapClient
    private let transport: AsyncTransport
    public private(set) var selectedMailbox: String?
    public private(set) var selectedState = ImapSelectedState()

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
        selectedMailbox = nil
        selectedState = ImapSelectedState()
    }

    public func capability() async throws -> ImapResponse? {
        try await client.capability()
    }

    public func login(user: String, password: String) async throws -> ImapResponse? {
        try await client.login(user: user, password: password)
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        let command = try await client.send(.select(mailbox))
        var emptyReads = 0
        var nextState = ImapSelectedState()

        while true {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                if emptyReads > 10 {
                    throw SessionError.timeout
                }
                continue
            }
            emptyReads = 0
            for message in messages {
                applySelectedState(&nextState, mailbox: mailbox, from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    selectedMailbox = mailbox
                    selectedState = nextState
                    return response
                }
            }
        }
    }

    public func close() async throws -> ImapResponse? {
        let response = try await client.close()
        if response?.isOk == true {
            selectedMailbox = nil
            selectedState = ImapSelectedState()
        }
        return response
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
                _ = ingestSelectedState(from: message)
                if let status = ImapStatusResponse.parse(message.line) {
                    result = status
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk, let result {
                        if selectedMailbox == mailbox {
                            selectedState.apply(status: result)
                        }
                        return result
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetch(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let result = try await fetchWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func fetchWithQresync(
        _ set: String,
        items: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        let command = try await client.send(.fetch(set, items))
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        return ImapFetchResult(responses: results, qresyncEvents: events)
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
                _ = ingestSelectedState(from: message)
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
                if let event = ingestSelectedState(from: message, validity: validity) {
                    events.append(event)
                }
            }
            if !events.isEmpty {
                return events
            }
        }
        throw SessionError.timeout
    }

    private func applySelectedState(_ state: inout ImapSelectedState, mailbox: String, from message: ImapLiteralMessage) {
        if let response = message.response {
            state.apply(response: response)
        } else if let response = ImapResponse.parse(message.line) {
            state.apply(response: response)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            state.apply(modSeq: modSeq)
        }
        if let status = ImapStatusResponse.parse(message.line), status.mailbox == mailbox {
            state.apply(status: status)
        }
        if let listStatus = ImapListStatusResponse.parse(message.line), listStatus.mailbox.name == mailbox {
            state.apply(listStatus: listStatus)
        }
        if let event = ImapQresyncEvent.parse(message, validity: state.uidValidity ?? 0) {
            state.apply(event: event)
        }
    }

    private func ingestSelectedState(from message: ImapLiteralMessage, validity: UInt32? = nil) -> ImapQresyncEvent? {
        if let response = message.response {
            selectedState.apply(response: response)
        } else if let response = ImapResponse.parse(message.line) {
            selectedState.apply(response: response)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            selectedState.apply(modSeq: modSeq)
        }
        if let status = ImapStatusResponse.parse(message.line),
           let selectedMailbox,
           status.mailbox == selectedMailbox {
            selectedState.apply(status: status)
        }
        if let listStatus = ImapListStatusResponse.parse(message.line),
           let selectedMailbox,
           listStatus.mailbox.name == selectedMailbox {
            selectedState.apply(listStatus: listStatus)
        }
        if let validity, validity > 0, selectedState.uidValidity == nil {
            selectedState.uidValidity = validity
        }
        let validity = validity ?? selectedState.uidValidity ?? 0
        if let event = ImapQresyncEvent.parse(message, validity: validity) {
            selectedState.apply(event: event)
            return event
        }
        return nil
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
