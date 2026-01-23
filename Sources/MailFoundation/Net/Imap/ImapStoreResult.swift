//
// ImapStoreResult.swift
//
// Typed STORE results with flag changes and QRESYNC events.
//

public struct ImapStoreResult: Sendable, Equatable {
    public let responses: [ImapFetchResponse]
    public let flagChanges: [ImapFlagChange]
    public let qresyncEvents: [ImapQresyncEvent]

    public init(
        responses: [ImapFetchResponse] = [],
        flagChanges: [ImapFlagChange] = [],
        qresyncEvents: [ImapQresyncEvent] = []
    ) {
        self.responses = responses
        self.flagChanges = flagChanges
        self.qresyncEvents = qresyncEvents
    }

    public init(fetchResult: ImapFetchResult) {
        self.responses = fetchResult.responses
        self.flagChanges = fetchResult.flagChanges
        self.qresyncEvents = fetchResult.qresyncEvents
    }
}
