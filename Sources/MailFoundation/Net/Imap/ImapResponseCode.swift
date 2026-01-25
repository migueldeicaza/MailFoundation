//
// ImapResponseCode.swift
//
// Parse IMAP response codes.
//

public enum ImapResponseCodeKind: Sendable, Equatable {
    case uidNext(UInt32)
    case uidValidity(UInt32)
    case highestModSeq(UInt64)
    case copyUid(ImapCopyUid)
}

public struct ImapResponseCode: Sendable, Equatable {
    public let kind: ImapResponseCodeKind

    public static func parseAll(_ text: String) -> [ImapResponseCode] {
        var results: [ImapResponseCode] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard let open = text[index...].firstIndex(of: "[") else { break }
            guard let close = text[open...].firstIndex(of: "]") else { break }
            let inner = text[text.index(after: open)..<close]
            if let code = parseCode(String(inner)) {
                results.append(code)
            }
            index = text.index(after: close)
        }

        return results
    }

    private static func parseCode(_ text: String) -> ImapResponseCode? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 2 else { return nil }
        let name = tokens[0].uppercased()
        let value = tokens[1]
        switch name {
        case "UIDNEXT":
            if let number = UInt32(value) {
                return ImapResponseCode(kind: .uidNext(number))
            }
        case "UIDVALIDITY":
            if let number = UInt32(value) {
                return ImapResponseCode(kind: .uidValidity(number))
            }
        case "HIGHESTMODSEQ":
            if let number = UInt64(value) {
                return ImapResponseCode(kind: .highestModSeq(number))
            }
        case "COPYUID":
            if let number = UInt32(value) {
                let sourceToken = tokens.count > 2 ? String(tokens[2]) : nil
                let destinationToken = tokens.count > 3 ? String(tokens[3]) : nil
                let source = sourceToken.flatMap { UniqueIdSet.tryParse($0, validity: number) }
                let destination = destinationToken.flatMap { UniqueIdSet.tryParse($0, validity: number) }
                let copyUid = ImapCopyUid(uidValidity: number, source: source, destination: destination)
                return ImapResponseCode(kind: .copyUid(copyUid))
            }
        default:
            break
        }
        return nil
    }
}

public struct ImapCopyUid: Sendable, Equatable {
    public let uidValidity: UInt32
    public let source: UniqueIdSet?
    public let destination: UniqueIdSet?
}

public extension ImapResponseCode {
    static func copyUid(from text: String) -> ImapCopyUid? {
        for code in parseAll(text) {
            if case let .copyUid(value) = code.kind {
                return value
            }
        }
        return nil
    }
}
