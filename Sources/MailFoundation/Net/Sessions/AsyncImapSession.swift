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

    public func noop() async throws -> ImapResponse? {
        let command = try await client.send(.noop)
        var emptyReads = 0
        while emptyReads < 10 {
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func enable(_ capabilities: [String], maxEmptyReads: Int = 10) async throws -> [String] {
        try await ensureAuthenticated()
        let command = try await client.send(.enable(capabilities))
        var enabled: [String] = []
        var emptyReads = 0
        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in messages {
                if let response = ImapEnabledResponse.parse(message.line) {
                    enabled.append(contentsOf: response.capabilities)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return enabled
                }
            }
        }
        throw SessionError.timeout
    }

    public func select(mailbox: String) async throws -> ImapResponse? {
        try await ensureAuthenticated()
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

    public func examine(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse? {
        try await ensureAuthenticated()
        let command = try await client.send(.examine(mailbox))
        var emptyReads = 0
        var nextState = ImapSelectedState()

        while emptyReads < maxEmptyReads {
            let messages = await client.nextMessages()
            if messages.isEmpty {
                emptyReads += 1
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
        throw SessionError.timeout
    }

    public func close() async throws -> ImapResponse? {
        try await ensureSelected()
        let response = try await client.close()
        if response?.isOk == true {
            selectedMailbox = nil
            selectedState = ImapSelectedState()
        }
        return response
    }

    public func check(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureSelected()
        let command = try await client.send(.check)
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func expunge(maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureSelected()
        let command = try await client.send(.expunge)
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
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func create(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        let command = try await client.send(.create(mailbox))
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func delete(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        let command = try await client.send(.delete(mailbox))
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func rename(mailbox: String, newName: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        let command = try await client.send(.rename(mailbox, newName))
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func subscribe(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        let command = try await client.send(.subscribe(mailbox))
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func unsubscribe(mailbox: String, maxEmptyReads: Int = 10) async throws -> ImapResponse {
        try await ensureAuthenticated()
        let command = try await client.send(.unsubscribe(mailbox))
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
                    return response
                }
            }
        }
        throw SessionError.timeout
    }

    public func list(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await listResponses(reference: reference, mailbox: mailbox, maxEmptyReads: maxEmptyReads)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func listResponses(
        reference: String,
        mailbox: String,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await ensureAuthenticated()
        let command = try await client.send(.list(reference, mailbox))
        var responses: [ImapMailboxListResponse] = []
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
                if let list = ImapMailboxListResponse.parse(message.line) {
                    responses.append(list)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    public func lsub(reference: String, mailbox: String, maxEmptyReads: Int = 10) async throws -> [ImapMailbox] {
        let responses = try await lsubResponses(reference: reference, mailbox: mailbox, maxEmptyReads: maxEmptyReads)
        return responses.map { ImapMailbox(kind: $0.kind, name: $0.name, delimiter: $0.delimiter, attributes: $0.attributes) }
    }

    public func lsubResponses(
        reference: String,
        mailbox: String,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapMailboxListResponse] {
        try await ensureAuthenticated()
        let command = try await client.send(.lsub(reference, mailbox))
        var responses: [ImapMailboxListResponse] = []
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
                if let list = ImapMailboxListResponse.parse(message.line) {
                    responses.append(list)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    public func listStatus(
        reference: String,
        mailbox: String,
        maxEmptyReads: Int = 10
    ) async throws -> [ImapListStatusResponse] {
        try await ensureAuthenticated()
        let command = try await client.send(.list(reference, mailbox))
        var responses: [ImapListStatusResponse] = []
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
                if let listStatus = ImapListStatusResponse.parse(message.line) {
                    responses.append(listStatus)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    guard response.isOk else {
                        throw SessionError.imapError(status: response.status, text: response.text)
                    }
                    return responses
                }
            }
        }
        throw SessionError.timeout
    }

    public func capabilities() async -> ImapCapabilities? {
        await client.capabilities
    }

    public func search(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await ensureSelected()
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

    public func search(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await search(query.serialize(), maxEmptyReads: maxEmptyReads)
    }

    public func uidSearch(_ criteria: String, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await ensureSelected()
        let command = try await client.send(.uidSearch(criteria))
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

    public func uidSearch(_ query: SearchQuery, maxEmptyReads: Int = 10) async throws -> ImapSearchResponse {
        try await uidSearch(query.serialize(), maxEmptyReads: maxEmptyReads)
    }

    public func status(mailbox: String, items: [String], maxEmptyReads: Int = 10) async throws -> ImapStatusResponse {
        try await ensureAuthenticated()
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
        try await ensureSelected()
        let result = try await fetchWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func fetch(_ set: String, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        try await fetch(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
    }

    public func fetchSummaries(
        _ set: String,
        request: FetchRequest,
        previewLength: Int = 512,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || request.items.contains(.previewText)
        let itemList = request.items.contains(.previewText)
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        return try await fetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies, maxEmptyReads: maxEmptyReads)
    }

    public func fetchWithQresync(
        _ set: String,
        items: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
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

    public func fetchSummariesWithQresync(
        _ set: String,
        items: String,
        parseBodies: Bool,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        let command = try await client.send(.fetch(set, items))
        var messages: [ImapLiteralMessage] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let batch = await client.nextMessages()
            if batch.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            messages.append(contentsOf: batch)
            for message in batch {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        let fetches = messages.compactMap { ImapFetchResponse.parse($0.line) }
                        let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                        let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                        return fetches.compactMap { fetch in
                            MessageSummary.build(fetch: fetch, bodyMap: mapBySequence[fetch.sequence])
                        }
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func fetchBodySections(_ set: String, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchBodyMap] {
        let result = try await fetchBodySectionsWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.bodies
    }

    public func fetchBodySectionsWithQresync(
        _ set: String,
        items: String,
        validity: UInt32? = nil,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchBodyQresyncResult {
        try await ensureSelected()
        let command = try await client.send(.fetch(set, items))
        var messages: [ImapLiteralMessage] = []
        var events: [ImapQresyncEvent] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let batch = await client.nextMessages()
            if batch.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            for message in batch {
                messages.append(message)
                if let event = ingestSelectedState(from: message, validity: validity) {
                    events.append(event)
                }
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        let bodies = ImapFetchBodyParser.parseMaps(messages)
                        return ImapFetchBodyQresyncResult(bodies: bodies, qresyncEvents: events)
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidFetch(_ set: UniqueIdSet, items: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let result = try await uidFetchWithQresync(set, items: items, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func uidFetch(_ set: UniqueIdSet, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        try await uidFetch(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
    }

    public func uidFetchSummaries(
        _ set: UniqueIdSet,
        request: FetchRequest,
        previewLength: Int = 512,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        let needsBodies = request.items.contains(.headers) || request.items.contains(.references) || request.items.contains(.previewText)
        let itemList = request.items.contains(.previewText)
            ? request.imapItemList(previewFallback: ImapFetchPartial(start: 0, length: previewLength))
            : request.imapItemList
        return try await uidFetchSummariesWithQresync(set, items: itemList, parseBodies: needsBodies, maxEmptyReads: maxEmptyReads)
    }

    public func uidFetchWithQresync(
        _ set: UniqueIdSet,
        items: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
        let command = try await client.send(.uidFetch(set.description, items))
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

    public func uidFetchSummariesWithQresync(
        _ set: UniqueIdSet,
        items: String,
        parseBodies: Bool,
        maxEmptyReads: Int = 10
    ) async throws -> [MessageSummary] {
        try await ensureSelected()
        let command = try await client.send(.uidFetch(set.description, items))
        var messages: [ImapLiteralMessage] = []
        var emptyReads = 0

        while emptyReads < maxEmptyReads {
            let batch = await client.nextMessages()
            if batch.isEmpty {
                emptyReads += 1
                continue
            }
            emptyReads = 0
            messages.append(contentsOf: batch)
            for message in batch {
                _ = ingestSelectedState(from: message)
                if let response = message.response, case let .tagged(tag) = response.kind, tag == command.tag {
                    if response.isOk {
                        let fetches = messages.compactMap { ImapFetchResponse.parse($0.line) }
                        let maps = parseBodies ? ImapFetchBodyParser.parseMaps(messages) : []
                        let mapBySequence = Dictionary(uniqueKeysWithValues: maps.map { ($0.sequence, $0) })
                        return fetches.compactMap { fetch in
                            MessageSummary.build(fetch: fetch, bodyMap: mapBySequence[fetch.sequence])
                        }
                    }
                    throw SessionError.imapError(status: response.status, text: response.text)
                }
            }
        }

        throw SessionError.timeout
    }

    public func uidStore(_ set: UniqueIdSet, data: String, maxEmptyReads: Int = 10) async throws -> [ImapFetchResponse] {
        let result = try await uidStoreWithQresync(set, data: data, maxEmptyReads: maxEmptyReads)
        return result.responses
    }

    public func uidStoreResult(
        _ set: UniqueIdSet,
        data: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapStoreResult {
        let result = try await uidStoreWithQresync(set, data: data, maxEmptyReads: maxEmptyReads)
        return ImapStoreResult(fetchResult: result)
    }

    public func uidStoreWithQresync(
        _ set: UniqueIdSet,
        data: String,
        maxEmptyReads: Int = 10
    ) async throws -> ImapFetchResult {
        try await ensureSelected()
        let command = try await client.send(.uidStore(set.description, data))
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

    public func fetchAttributes(_ set: String, request: FetchRequest, maxEmptyReads: Int = 10) async throws -> [ImapFetchAttributes] {
        try await fetchAttributes(set, items: request.imapItemList, maxEmptyReads: maxEmptyReads)
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
        try await ensureSelected()
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
        try await ensureSelected()
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
        try await ensureSelected()
        _ = try await client.send(.idleDone)
    }

    public func readQresyncEvents(validity: UInt32 = 0, maxEmptyReads: Int = 10) async throws -> [ImapQresyncEvent] {
        try await ensureSelected()
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

    private func ensureAuthenticated() async throws {
        let current = ImapSessionState(await client.state)
        guard current == .authenticated || current == .selected else {
            throw SessionError.invalidImapState(expected: .authenticated, actual: current)
        }
    }

    private func ensureSelected() async throws {
        let current = ImapSessionState(await client.state)
        guard current == .selected else {
            throw SessionError.invalidImapState(expected: .selected, actual: current)
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

@available(macOS 10.15, iOS 13.0, *)
extension AsyncImapSession: AsyncMailService {
    public typealias ConnectResponse = ImapResponse?

    public var state: MailServiceState {
        get async {
            let clientState = await client.state
            switch clientState {
            case .disconnected:
                return .disconnected
            case .connected, .authenticating:
                return .connected
            case .authenticated, .selected:
                return .authenticated
            }
        }
    }

    public var isConnected: Bool {
        get async {
            let clientState = await client.state
            return clientState != .disconnected
        }
    }

    public var isAuthenticated: Bool {
        get async {
            let clientState = await client.state
            return clientState == .authenticated || clientState == .selected
        }
    }
}
