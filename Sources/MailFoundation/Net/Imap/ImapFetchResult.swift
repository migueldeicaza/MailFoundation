//
// ImapFetchResult.swift
//
// FETCH results with QRESYNC event aggregation.
//

public struct ImapFetchResult: Sendable, Equatable {
    public let responses: [ImapFetchResponse]
    public let qresyncEvents: [ImapQresyncEvent]

    public init(responses: [ImapFetchResponse] = [], qresyncEvents: [ImapQresyncEvent] = []) {
        self.responses = responses
        self.qresyncEvents = qresyncEvents
    }
}
