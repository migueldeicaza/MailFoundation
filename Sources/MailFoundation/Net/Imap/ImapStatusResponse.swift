//
// ImapStatusResponse.swift
//
// IMAP STATUS response parsing helpers.
//

public struct ImapStatusResponse: Sendable, Equatable {
    public let mailbox: String
    public let items: [String: Int]

    public static func parse(_ line: String) -> ImapStatusResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("* STATUS ") else {
            return nil
        }

        let restStart = trimmed.index(trimmed.startIndex, offsetBy: 9)
        let rest = trimmed[restStart...]
        guard let openParen = rest.firstIndex(of: "("), let closeParen = rest.firstIndex(of: ")"), closeParen > openParen else {
            return nil
        }

        let mailboxPart = rest[..<openParen].trimmingCharacters(in: .whitespaces)
        let itemsPart = rest[rest.index(after: openParen)..<closeParen]
        let tokens = itemsPart.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 2 else { return nil }

        var items: [String: Int] = [:]
        var index = 0
        while index + 1 < tokens.count {
            let key = tokens[index].uppercased()
            let value = Int(tokens[index + 1]) ?? 0
            items[key] = value
            index += 2
        }

        return ImapStatusResponse(mailbox: String(mailboxPart), items: items)
    }
}
