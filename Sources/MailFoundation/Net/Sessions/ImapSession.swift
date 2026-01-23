//
// ImapSession.swift
//
// Higher-level synchronous IMAP session helpers.
//

public final class ImapSession {
    private let client: ImapClient
    private let transport: Transport
    private let maxReads: Int
    public private(set) var selectedMailbox: String?
    public private(set) var selectedState = ImapSelectedState()

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
        selectedMailbox = nil
        selectedState = ImapSelectedState()
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
        var reads = 0
        var nextState = ImapSelectedState()

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

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

        throw SessionError.timeout
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
        let result = try fetchWithQresync(set, items: items)
        return result.responses
    }

    public func fetchWithQresync(_ set: String, items: String) throws -> ImapFetchResult {
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchBodySections(_ set: String, items: String) throws -> [ImapFetchBodyMap] {
        let result = try fetchBodySectionsWithQresync(set, items: items)
        return result.bodies
    }

    public func fetchBodySectionsWithQresync(
        _ set: String,
        items: String,
        validity: UInt32? = nil
    ) throws -> ImapFetchBodyQresyncResult {
        let command = client.send(.fetch(set, items))
        try ensureWrite()
        var reads = 0
        var messages: [ImapLiteralMessage] = []
        var events: [ImapQresyncEvent] = []

        while reads < maxReads {
            let batch = client.receiveWithLiterals()
            if batch.isEmpty {
                reads += 1
                continue
            }

            for message in batch {
                messages.append(message)
                if let event = ingestSelectedState(from: message, validity: validity) {
                    events.append(event)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    let bodies = ImapFetchBodyParser.parseMaps(messages)
                    return ImapFetchBodyQresyncResult(bodies: bodies, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidFetch(_ set: UniqueIdSet, items: String) throws -> [ImapFetchResponse] {
        let result = try uidFetchWithQresync(set, items: items)
        return result.responses
    }

    public func uidFetchWithQresync(_ set: UniqueIdSet, items: String) throws -> ImapFetchResult {
        let command = client.send(.uidFetch(set.description, items))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidStore(_ set: UniqueIdSet, data: String) throws -> [ImapFetchResponse] {
        let result = try uidStoreWithQresync(set, data: data)
        return result.responses
    }

    public func uidStoreResult(_ set: UniqueIdSet, data: String) throws -> ImapStoreResult {
        let result = try uidStoreWithQresync(set, data: data)
        return ImapStoreResult(fetchResult: result)
    }

    public func uidStoreWithQresync(_ set: UniqueIdSet, data: String) throws -> ImapFetchResult {
        let command = client.send(.uidStore(set.description, data))
        try ensureWrite()
        var results: [ImapFetchResponse] = []
        var events: [ImapQresyncEvent] = []
        var reads = 0

        while reads < maxReads {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }

            for message in messages {
                if let event = ingestSelectedState(from: message) {
                    events.append(event)
                }
                if let fetch = ImapFetchResponse.parse(message.line) {
                    results.append(fetch)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return ImapFetchResult(responses: results, qresyncEvents: events)
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
                _ = ingestSelectedState(from: message)
                if let status = ImapStatusResponse.parse(message.line) {
                    result = status
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    if let result {
                        if selectedMailbox == mailbox {
                            selectedState.apply(status: result)
                        }
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
                _ = ingestSelectedState(from: message)
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

    public func stopIdle() throws {
        _ = client.send(.idleDone)
        try ensureWrite()
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxReads: Int? = nil) -> [ImapQresyncEvent] {
        let limit = maxReads ?? self.maxReads
        var reads = 0
        var events: [ImapQresyncEvent] = []
        while reads < limit {
            let messages = client.receiveWithLiterals()
            if messages.isEmpty {
                reads += 1
                continue
            }
            for message in messages {
                if let event = ingestSelectedState(from: message, validity: validity) {
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

    private func applySelectedState(_ state: inout ImapSelectedState, mailbox: String, from message: ImapLiteralMessage) {
        if let response = message.response {
            state.apply(response: response)
        } else if let response = ImapResponse.parse(message.line) {
            state.apply(response: response)
        }
        if let idle = ImapIdleEvent.parse(message.line) {
            state.apply(event: idle)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            state.apply(modSeq: modSeq)
        }
        if let fetch = ImapFetchResponse.parse(message.line),
           let attrs = ImapFetchAttributes.parse(fetch) {
            state.applyFetch(sequence: fetch.sequence, uid: attrs.uid, modSeq: attrs.modSeq)
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
        if let idle = ImapIdleEvent.parse(message.line) {
            selectedState.apply(event: idle)
        }
        if let modSeq = ImapModSeqResponse.parse(message.line) {
            selectedState.apply(modSeq: modSeq)
        }
        if let fetch = ImapFetchResponse.parse(message.line),
           let attrs = ImapFetchAttributes.parse(fetch) {
            selectedState.applyFetch(sequence: fetch.sequence, uid: attrs.uid, modSeq: attrs.modSeq)
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
}
