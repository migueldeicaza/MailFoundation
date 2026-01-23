//
// ImapEnabledResponse.swift
//
// Parse ENABLED response from IMAP ENABLE command.
//

public struct ImapEnabledResponse: Sendable, Equatable {
    public let capabilities: [String]

    public static func parse(_ line: String) -> ImapEnabledResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("* ENABLED") else { return nil }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "*", parts[1].uppercased() == "ENABLED" else {
            return nil
        }
        let capabilities = parts.dropFirst(2).map(String.init)
        return ImapEnabledResponse(capabilities: capabilities)
    }
}
