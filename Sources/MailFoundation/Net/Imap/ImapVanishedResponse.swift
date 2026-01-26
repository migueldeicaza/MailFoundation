//
// ImapVanishedResponse.swift
//
// Parse QRESYNC VANISHED responses.
//

public struct ImapVanishedResponse: Sendable, Equatable {
    public let earlier: Bool
    public let uids: UniqueIdSet

    public static func parse(_ line: String, validity: UInt32 = 0) -> ImapVanishedResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("* VANISHED") else {
            return nil
        }

        var rest = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
        guard rest.uppercased().hasPrefix("VANISHED") else { return nil }
        rest = rest.dropFirst("VANISHED".count).trimmingCharacters(in: .whitespaces)

        var earlier = false
        if rest.hasPrefix("(") {
            guard let close = rest.firstIndex(of: ")") else { return nil }
            let inner = rest[rest.index(after: rest.startIndex)..<close]
            if inner.uppercased().contains("EARLIER") {
                earlier = true
            }
            rest = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }

        guard let set = try? UniqueIdSet(parsing: String(rest), validity: validity) else {
            return nil
        }
        return ImapVanishedResponse(earlier: earlier, uids: set)
    }
}

public extension ImapVanishedResponse {
    static func == (lhs: ImapVanishedResponse, rhs: ImapVanishedResponse) -> Bool {
        lhs.earlier == rhs.earlier && lhs.uids.description == rhs.uids.description
    }
}
