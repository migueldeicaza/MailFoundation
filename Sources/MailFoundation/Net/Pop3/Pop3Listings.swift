//
// Pop3Listings.swift
//
// POP3 LIST/UIDL/STAT parsing helpers.
//

public struct Pop3ListItem: Sendable, Equatable {
    public let index: Int
    public let size: Int

    public static func parseLine(_ line: String) -> Pop3ListItem? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let index = Int(parts[0]),
              let size = Int(parts[1]) else {
            return nil
        }
        return Pop3ListItem(index: index, size: size)
    }
}

public struct Pop3UidlItem: Sendable, Equatable {
    public let index: Int
    public let uid: String

    public static func parseLine(_ line: String) -> Pop3UidlItem? {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let index = Int(parts[0]) else {
            return nil
        }
        return Pop3UidlItem(index: index, uid: String(parts[1]))
    }
}

public struct Pop3StatResponse: Sendable, Equatable {
    public let count: Int
    public let size: Int

    public static func parse(_ response: Pop3Response) -> Pop3StatResponse? {
        guard response.isSuccess else { return nil }
        let parts = response.message.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let count = Int(parts[0]),
              let size = Int(parts[1]) else {
            return nil
        }
        return Pop3StatResponse(count: count, size: size)
    }
}

public enum Pop3ListParser {
    public static func parse(_ lines: [String]) -> [Pop3ListItem] {
        lines.compactMap(Pop3ListItem.parseLine)
    }
}

public enum Pop3UidlParser {
    public static func parse(_ lines: [String]) -> [Pop3UidlItem] {
        lines.compactMap(Pop3UidlItem.parseLine)
    }
}
