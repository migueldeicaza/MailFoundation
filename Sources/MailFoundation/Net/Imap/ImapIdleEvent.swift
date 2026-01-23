//
// ImapIdleEvent.swift
//
// IMAP IDLE event parsing.
//

public enum ImapIdleEvent: Sendable, Equatable {
    case exists(Int)
    case expunge(Int)
    case recent(Int)
    case flags([String])
    case status(ImapResponseStatus?, String)
    case other(String)

    public static func parse(_ line: String) -> ImapIdleEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") else { return nil }

        if let response = ImapResponse.parse(trimmed),
           case .untagged = response.kind,
           let status = response.status {
            return .status(status, response.text)
        }

        if trimmed.uppercased().hasPrefix("* FLAGS") {
            let startIndex = trimmed.firstIndex(of: "(")
            let endIndex = trimmed.lastIndex(of: ")")
            if let startIndex, let endIndex, startIndex < endIndex {
                let inner = trimmed[trimmed.index(after: startIndex)..<endIndex]
                let flags = inner.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                return .flags(flags)
            }
        }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return .other(trimmed) }
        guard let number = Int(parts[1]) else { return .other(trimmed) }
        let keyword = parts[2].uppercased()
        switch keyword {
        case "EXISTS":
            return .exists(number)
        case "EXPUNGE":
            return .expunge(number)
        case "RECENT":
            return .recent(number)
        default:
            break
        }

        return .other(trimmed)
    }
}
