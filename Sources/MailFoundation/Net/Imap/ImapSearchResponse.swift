//
// ImapSearchResponse.swift
//
// IMAP SEARCH response parsing helpers.
//

public struct ImapSearchResponse: Sendable, Equatable {
    public let ids: [UInt32]

    public static func parse(_ line: String) -> ImapSearchResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        let upper = trimmed.uppercased()
        guard upper.hasPrefix("* SEARCH") else { return nil }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 8)
        let remainder = trimmed[startIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else {
            return ImapSearchResponse(ids: [])
        }

        let tokens = remainder.split(separator: " ", omittingEmptySubsequences: true)
        var ids: [UInt32] = []
        for token in tokens {
            if let id = UInt32(token) {
                ids.append(id)
            }
        }
        return ImapSearchResponse(ids: ids)
    }
}
