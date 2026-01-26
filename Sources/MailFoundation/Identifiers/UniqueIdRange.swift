//
// UniqueIdRange.swift
//
// Ported from MailKit (C#) to Swift.
//

public enum UniqueIdRangeParseError: Error, Sendable {
    case invalidToken
}

public struct UniqueIdRange: Sendable, Sequence, CustomStringConvertible {
    public static let all = UniqueIdRange(validity: 0, start: UniqueId.minValue.id, end: UniqueId.maxValue.id)

    public let validity: UInt32
    private let start: UInt32
    private let end: UInt32

    public init(validity: UInt32, start: UInt32, end: UInt32) {
        precondition(start != 0, "UniqueIdRange start must be non-zero.")
        precondition(end != 0, "UniqueIdRange end must be non-zero.")
        self.validity = validity
        self.start = start
        self.end = end
    }

    public init(start: UniqueId, end: UniqueId) {
        precondition(start.isValid, "UniqueIdRange start must be valid.")
        precondition(end.isValid, "UniqueIdRange end must be valid.")
        self.validity = start.validity
        self.start = start.id
        self.end = end.id
    }

    public var sortOrder: SortOrder {
        start <= end ? .ascending : .descending
    }

    public var min: UniqueId {
        if start < end {
            return UniqueId(validity: validity, id: start)
        }
        return UniqueId(validity: validity, id: end)
    }

    public var max: UniqueId {
        if start > end {
            return UniqueId(validity: validity, id: start)
        }
        return UniqueId(validity: validity, id: end)
    }

    public var startId: UniqueId {
        UniqueId(validity: validity, id: start)
    }

    public var endId: UniqueId {
        UniqueId(validity: validity, id: end)
    }

    public var count: Int {
        let delta = start <= end ? end - start : start - end
        let length = UInt64(delta) + 1
        return length > UInt64(Int.max) ? Int.max : Int(length)
    }

    public func contains(_ uid: UniqueId) -> Bool {
        if start <= end {
            return uid.id >= start && uid.id <= end
        }

        return uid.id <= start && uid.id >= end
    }

    public func index(of uid: UniqueId) -> Int? {
        if start <= end {
            guard uid.id >= start && uid.id <= end else {
                return nil
            }
            return Int(uid.id - start)
        }

        guard uid.id <= start && uid.id >= end else {
            return nil
        }
        return Int(start - uid.id)
    }

    public subscript(index: Int) -> UniqueId {
        precondition(index >= 0 && index < count, "Index out of range.")
        let uid = start <= end ? start + UInt32(index) : start - UInt32(index)
        return UniqueId(validity: validity, id: uid)
    }

    public func copy(to array: inout [UniqueId], startingAt index: Int) {
        precondition(index >= 0, "Index out of range.")
        precondition(index <= array.count, "Index out of range.")
        precondition(array.count - index >= count, "Destination array is too small.")

        var currentIndex = index
        for uid in self {
            array[currentIndex] = uid
            currentIndex += 1
        }
    }

    public func makeIterator() -> AnyIterator<UniqueId> {
        var current = start
        let isAscending = start <= end
        var done = false

        return AnyIterator {
            if done {
                return nil
            }

            let uid = UniqueId(validity: validity, id: current)

            if isAscending {
                if current == end {
                    done = true
                } else {
                    current += 1
                }
            } else {
                if current == end {
                    done = true
                } else {
                    current -= 1
                }
            }

            return uid
        }
    }

    public var description: String {
        if end == UInt32.max {
            return "\(start):*"
        }
        return "\(start):\(end)"
    }

    public init(parsing token: String, validity: UInt32 = 0) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        var index = 0

        func skipWhitespace(_ bytes: [UInt8], _ index: inout Int) {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 32 || byte == 9 {
                    index += 1
                } else {
                    break
                }
            }
        }

        skipWhitespace(bytes, &index)
        guard let parsedStart = UniqueId.parseNonZeroUInt32(bytes: bytes, index: &index) else {
            throw UniqueIdRangeParseError.invalidToken
        }

        skipWhitespace(bytes, &index)
        guard index < bytes.count, bytes[index] == 58 else {
            throw UniqueIdRangeParseError.invalidToken
        }
        index += 1
        skipWhitespace(bytes, &index)

        let parsedEnd: UInt32
        if index < bytes.count, bytes[index] == 42 {
            index += 1
            skipWhitespace(bytes, &index)
            guard index == bytes.count else {
                throw UniqueIdRangeParseError.invalidToken
            }
            parsedEnd = UInt32.max
        } else {
            guard let end = UniqueId.parseNonZeroUInt32(bytes: bytes, index: &index) else {
                throw UniqueIdRangeParseError.invalidToken
            }
            skipWhitespace(bytes, &index)
            guard index == bytes.count else {
                throw UniqueIdRangeParseError.invalidToken
            }
            parsedEnd = end
        }

        self.validity = validity
        self.start = parsedStart
        self.end = parsedEnd
    }
}
