//
// ImapQresyncEvent.swift
//
// QRESYNC event parsing helpers.
//

public struct ImapFetchModSeqEvent: Sendable, Equatable {
    public let sequence: Int
    public let uid: UInt32?
    public let modSeq: UInt64
}

public enum ImapQresyncEvent: Sendable, Equatable {
    case vanished(ImapVanishedResponse)
    case fetch(ImapFetchModSeqEvent)
}

public extension ImapQresyncEvent {
    static func parse(_ line: String, validity: UInt32 = 0) -> ImapQresyncEvent? {
        if let vanished = ImapVanishedResponse.parse(line, validity: validity) {
            return .vanished(vanished)
        }
        if let fetch = ImapFetchResponse.parse(line),
           let attrs = ImapFetchAttributes.parse(fetch),
           let modSeq = attrs.modSeq {
            return .fetch(ImapFetchModSeqEvent(sequence: fetch.sequence, uid: attrs.uid, modSeq: modSeq))
        }
        return nil
    }

    static func parse(_ message: ImapLiteralMessage, validity: UInt32 = 0) -> ImapQresyncEvent? {
        parse(message.line, validity: validity)
    }
}
