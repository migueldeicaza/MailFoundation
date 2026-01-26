//
// UniqueId.swift
//
// Ported from MailKit (C#) to Swift.
//

import Foundation

public enum UniqueIdParseError: Error, Sendable {
    case invalidToken
}

public struct UniqueId: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let invalid = UniqueId(validity: 0, id: 0, allowInvalid: true)
    public static let minValue = UniqueId(validity: 0, id: 1, allowInvalid: true)
    public static let maxValue = UniqueId(validity: 0, id: UInt32.max, allowInvalid: true)

    public let validity: UInt32
    public let id: UInt32

    public var isValid: Bool {
        id != 0
    }

    public init(validity: UInt32, id: UInt32) {
        precondition(id != 0, "UniqueId id must be non-zero.")
        self.validity = validity
        self.id = id
    }

    public init(id: UInt32) {
        self.init(validity: 0, id: id)
    }

    private init(validity: UInt32, id: UInt32, allowInvalid: Bool) {
        self.validity = validity
        self.id = id
    }

    public static func < (lhs: UniqueId, rhs: UniqueId) -> Bool {
        lhs.id < rhs.id
    }

    public var description: String {
        String(id)
    }

    public init(parsing token: String, validity: UInt32 = 0) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        var index = 0
        guard let parsed = Self.parseNonZeroUInt32(bytes: bytes, index: &index), index == bytes.count else {
            throw UniqueIdParseError.invalidToken
        }

        self.validity = validity
        self.id = parsed
    }

    internal static func parseNonZeroUInt32(bytes: [UInt8], index: inout Int) -> UInt32? {
        var value: UInt32 = 0
        var hasDigits = false
        let maxDiv10 = UInt32.max / 10
        let maxMod10 = UInt32.max % 10

        while index < bytes.count {
            let byte = bytes[index]
            if byte < 48 || byte > 57 {
                break
            }

            let digit = UInt32(byte - 48)
            hasDigits = true

            if value > maxDiv10 || (value == maxDiv10 && digit > maxMod10) {
                return nil
            }

            value = (value * 10) + digit
            index += 1
        }

        guard hasDigits, value != 0 else {
            return nil
        }

        return value
    }
}
