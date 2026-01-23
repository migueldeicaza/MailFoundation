//
// SequenceSet.swift
//
// IMAP message sequence set helper.
//

import Foundation

public enum SequenceSetParseError: Error, Sendable {
    case invalidToken
}

public struct SequenceSet: Sendable, Sequence, CustomStringConvertible {
    private struct Range: Sendable {
        var start: UInt32
        var end: UInt32

        var count: Int {
            let delta = start <= end ? end - start : start - end
            let length = UInt64(delta) + 1
            return length > UInt64(Int.max) ? Int.max : Int(length)
        }

        func contains(_ value: UInt32) -> Bool {
            if start <= end {
                return value >= start && value <= end
            }
            return value <= start && value >= end
        }

        subscript(index: Int) -> UInt32 {
            if start <= end {
                return start + UInt32(index)
            }
            return start - UInt32(index)
        }

        func serialized() -> String {
            if start == end {
                return SequenceSet.formatSequence(start)
            }

            if start <= end && end == UInt32.max {
                return "\(start):*"
            }

            let startText = SequenceSet.formatSequence(start)
            let endText = SequenceSet.formatSequence(end)
            return "\(startText):\(endText)"
        }
    }

    private var ranges: [Range] = []
    private var totalCount: Int64 = 0

    public private(set) var sortOrder: SortOrder

    public init(sortOrder: SortOrder = .none) {
        self.sortOrder = sortOrder
    }

    public init(_ sequences: [UInt32], sortOrder: SortOrder = .none) {
        self.sortOrder = sortOrder
        guard !sequences.isEmpty else { return }
        let result = SequenceSet.buildRanges(from: sequences)
        self.ranges = result.ranges
        self.totalCount = result.totalCount
        if sortOrder == .none {
            self.sortOrder = result.sortOrder
        }
    }

    public init(_ sequences: [Int], sortOrder: SortOrder = .none) {
        let mapped = sequences.map { UInt32($0) }
        self.init(mapped, sortOrder: sortOrder)
    }

    public var count: Int {
        totalCount > Int64(Int.max) ? Int.max : Int(totalCount)
    }

    public var isEmpty: Bool {
        totalCount == 0
    }

    public func contains(_ value: UInt32) -> Bool {
        for range in ranges where range.contains(value) {
            return true
        }
        return false
    }

    public func makeIterator() -> AnyIterator<UInt32> {
        var rangeIndex = 0
        var elementIndex = 0

        return AnyIterator {
            guard rangeIndex < ranges.count else {
                return nil
            }

            let range = ranges[rangeIndex]
            let value = range[elementIndex]
            elementIndex += 1

            if elementIndex >= range.count {
                rangeIndex += 1
                elementIndex = 0
            }

            return value
        }
    }

    public var description: String {
        ranges.map { $0.serialized() }.joined(separator: ",")
    }

    public static func tryParse(_ token: String) -> SequenceSet? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var set = SequenceSet()
        var order: SortOrder = .none
        var sorted = true
        var prev: UInt32 = 0

        for part in parts {
            let segment = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { return nil }
            let pieces = segment.split(separator: ":", omittingEmptySubsequences: false)
            if pieces.count == 1 {
                guard let value = parseToken(String(pieces[0])) else { return nil }
                set.ranges.append(Range(start: value, end: value))
                set.totalCount += 1

                if sorted && set.ranges.count > 1 {
                    switch order {
                    case .none:
                        order = value >= prev ? .ascending : .descending
                    case .descending:
                        sorted = value <= prev
                    case .ascending:
                        sorted = value >= prev
                    }
                }
                prev = value
            } else if pieces.count == 2 {
                guard let start = parseToken(String(pieces[0])) else { return nil }
                guard let end = parseToken(String(pieces[1])) else { return nil }

                let range = Range(start: start, end: end)
                set.totalCount += Int64(range.count)
                set.ranges.append(range)

                if sorted {
                    switch order {
                    case .none:
                        order = start <= end ? .ascending : .descending
                    case .descending:
                        sorted = start >= end && start <= prev
                    case .ascending:
                        sorted = start <= end && start >= prev
                    }
                }
                prev = end
            } else {
                return nil
            }
        }

        set.sortOrder = sorted ? order : .none
        return set
    }

    public static func parse(_ token: String) throws -> SequenceSet {
        guard let set = tryParse(token) else {
            throw SequenceSetParseError.invalidToken
        }
        return set
    }

    private static func parseToken(_ value: String) -> UInt32? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "*" {
            return UInt32.max
        }
        guard let number = UInt32(trimmed), number != 0 else {
            return nil
        }
        return number
    }

    private static func formatSequence(_ value: UInt32) -> String {
        value == UInt32.max ? "*" : String(value)
    }

    private static func buildRanges(from sequences: [UInt32]) -> (ranges: [Range], totalCount: Int64, sortOrder: SortOrder) {
        var ranges: [Range] = []
        var totalCount: Int64 = 0
        var sortOrder: SortOrder = .none
        var sorted = true

        var start = sequences[0]
        precondition(start != 0, "SequenceSet values must be non-zero.")
        var prev = start
        var direction: Int = 0

        for index in 1..<sequences.count {
            let value = sequences[index]
            precondition(value != 0, "SequenceSet values must be non-zero.")

            if sorted {
                if sortOrder == .none {
                    sortOrder = value >= prev ? .ascending : .descending
                } else if sortOrder == .ascending, value < prev {
                    sorted = false
                } else if sortOrder == .descending, value > prev {
                    sorted = false
                }
            }

            if direction == 0 {
                if value == prev + 1 {
                    direction = 1
                    prev = value
                    continue
                } else if prev > 1, value == prev - 1 {
                    direction = -1
                    prev = value
                    continue
                }
            } else if direction == 1, value == prev + 1 {
                prev = value
                continue
            } else if direction == -1, value == prev - 1 {
                prev = value
                continue
            }

            let range = Range(start: start, end: prev)
            ranges.append(range)
            totalCount += Int64(range.count)
            start = value
            prev = value
            direction = 0
        }

        let range = Range(start: start, end: prev)
        ranges.append(range)
        totalCount += Int64(range.count)

        if !sorted {
            sortOrder = .none
        }
        return (ranges, totalCount, sortOrder)
    }
}
