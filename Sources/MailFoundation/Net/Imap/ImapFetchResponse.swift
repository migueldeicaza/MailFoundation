//
// ImapFetchResponse.swift
//
// IMAP FETCH response parsing helpers.
//

public struct ImapFetchResponse: Sendable, Equatable {
    public let sequence: Int
    public let payload: String

    public static func parse(_ line: String) -> ImapFetchResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("* ") else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "*", let sequence = Int(parts[1]) else {
            return nil
        }
        let payload = String(parts[2])
        guard payload.uppercased().hasPrefix("FETCH") else { return nil }
        let payloadStart = payload.index(payload.startIndex, offsetBy: 5)
        let trimmedPayload = payload[payloadStart...].trimmingCharacters(in: .whitespaces)
        return ImapFetchResponse(sequence: sequence, payload: String(trimmedPayload))
    }
}
