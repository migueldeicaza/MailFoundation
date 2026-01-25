//
// ImapId.swift
//
// IMAP ID command helpers.
//

import Foundation

public enum ImapId {
    public static func buildArguments(_ parameters: [String: String?]?) -> String {
        guard let parameters, !parameters.isEmpty else {
            return "NIL"
        }

        let sortedKeys = parameters.keys.sorted()
        var tokens: [String] = []
        tokens.reserveCapacity(sortedKeys.count * 2)

        for key in sortedKeys {
            let value = parameters[key] ?? nil
            tokens.append(quote(key))
            if let value {
                tokens.append(quote(value))
            } else {
                tokens.append("NIL")
            }
        }

        return "(\(tokens.joined(separator: " ")))"
    }

    private static func quote(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
