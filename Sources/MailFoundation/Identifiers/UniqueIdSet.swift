//
// UniqueIdSet.swift
//
// Ported from MailKit (C#) to Swift.
//

public enum UniqueIdSetParseError: Error, Sendable {
    case invalidToken
    case invalidMaxLength
}

public struct UniqueIdSet: Sendable, Sequence, CustomStringConvertible {
    private struct Range: Sendable {
        var start: UInt32
        var end: UInt32

        var count: Int {
            let delta = start <= end ? end - start : start - end
            let length = UInt64(delta) + 1
            return length > UInt64(Int.max) ? Int.max : Int(length)
        }

        func contains(_ uid: UInt32) -> Bool {
            if start <= end {
                return uid >= start && uid <= end
            }
            return uid <= start && uid >= end
        }

        func index(of uid: UInt32) -> Int? {
            if start <= end {
                guard uid >= start && uid <= end else {
                    return nil
                }
                return Int(uid - start)
            }

            guard uid <= start && uid >= end else {
                return nil
            }
            return Int(start - uid)
        }

        subscript(index: Int) -> UInt32 {
            if start <= end {
                return start + UInt32(index)
            }
            return start - UInt32(index)
        }

        func makeIterator() -> AnyIterator<UInt32> {
            var current = start
            let isAscending = start <= end
            var done = false

            return AnyIterator {
                if done {
                    return nil
                }

                let value = current

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

                return value
            }
        }

        func serialized() -> String {
            if start == UInt32.max && end == UInt32.max {
                return "*"
            }
            if start == end {
                return UniqueIdSet.formatUid(start)
            }

            if start <= end && end == UInt32.max {
                return "\(start):*"
            }

            let startText = UniqueIdSet.formatUid(start)
            let endText = UniqueIdSet.formatUid(end)
            return "\(startText):\(endText)"
        }
    }

    private var ranges: [Range] = []
    private var totalCount: Int64 = 0

    public private(set) var sortOrder: SortOrder
    public private(set) var validity: UInt32

    public init(validity: UInt32, sortOrder: SortOrder = .none) {
        self.validity = validity
        self.sortOrder = sortOrder
    }

    public init(sortOrder: SortOrder = .none) {
        self.init(validity: 0, sortOrder: sortOrder)
    }

    public init(_ uids: [UniqueId], sortOrder: SortOrder = .none) {
        self.init(sortOrder: sortOrder)
        for uid in uids {
            add(uid)
        }
    }

    public var count: Int {
        totalCount > Int64(Int.max) ? Int.max : Int(totalCount)
    }

    public var isEmpty: Bool {
        totalCount == 0
    }

    private func indexOfRange(for uid: UInt32) -> Int? {
        guard !ranges.isEmpty else {
            return nil
        }

        if sortOrder != .none {
            return binarySearch(uid)
        }

        for index in ranges.indices {
            if ranges[index].contains(uid) {
                return index
            }
        }

        return nil
    }

    private func binarySearch(_ uid: UInt32) -> Int? {
        var minIndex = 0
        var maxIndex = ranges.count

        while minIndex < maxIndex {
            let i = minIndex + ((maxIndex - minIndex) / 2)
            let range = ranges[i]

            if sortOrder == .ascending {
                if uid >= range.start {
                    if uid <= range.end {
                        return i
                    }
                    minIndex = i + 1
                } else {
                    maxIndex = i
                }
            } else {
                if uid >= range.end {
                    if uid <= range.start {
                        return i
                    }
                    maxIndex = i
                } else {
                    minIndex = i + 1
                }
            }
        }

        return nil
    }

    private mutating func binaryInsertAscending(_ uid: UInt32) {
        var minIndex = 0
        var maxIndex = ranges.count
        var insertIndex = 0

        while minIndex < maxIndex {
            insertIndex = minIndex + ((maxIndex - minIndex) / 2)
            let range = ranges[insertIndex]

            if uid >= range.start {
                if uid <= range.end {
                    return
                }

                if uid == range.end + 1 {
                    if insertIndex + 1 < ranges.count, uid + 1 >= ranges[insertIndex + 1].start {
                        ranges[insertIndex] = Range(start: range.start, end: ranges[insertIndex + 1].end)
                        ranges.remove(at: insertIndex + 1)
                        totalCount += 1
                        return
                    }

                    ranges[insertIndex] = Range(start: range.start, end: uid)
                    totalCount += 1
                    return
                }

                minIndex = insertIndex + 1
                insertIndex = minIndex
            } else {
                if uid == range.start - 1 {
                    if insertIndex > 0, uid - 1 <= ranges[insertIndex - 1].end {
                        ranges[insertIndex - 1] = Range(start: ranges[insertIndex - 1].start, end: range.end)
                        ranges.remove(at: insertIndex)
                        totalCount += 1
                        return
                    }

                    ranges[insertIndex] = Range(start: uid, end: range.end)
                    totalCount += 1
                    return
                }

                maxIndex = insertIndex
            }
        }

        let range = Range(start: uid, end: uid)
        if insertIndex < ranges.count {
            ranges.insert(range, at: insertIndex)
        } else {
            ranges.append(range)
        }
        totalCount += 1
    }

    private mutating func binaryInsertDescending(_ uid: UInt32) {
        var minIndex = 0
        var maxIndex = ranges.count
        var insertIndex = 0

        while minIndex < maxIndex {
            insertIndex = minIndex + ((maxIndex - minIndex) / 2)
            let range = ranges[insertIndex]

            if uid <= range.start {
                if uid >= range.end {
                    return
                }

                if uid == range.end - 1 {
                    if insertIndex + 1 < ranges.count, uid - 1 <= ranges[insertIndex + 1].start {
                        ranges[insertIndex] = Range(start: range.start, end: ranges[insertIndex + 1].end)
                        ranges.remove(at: insertIndex + 1)
                        totalCount += 1
                        return
                    }

                    ranges[insertIndex] = Range(start: range.start, end: uid)
                    totalCount += 1
                    return
                }

                minIndex = insertIndex + 1
                insertIndex = minIndex
            } else {
                if uid == range.start + 1 {
                    if insertIndex > 0, uid + 1 >= ranges[insertIndex - 1].end {
                        ranges[insertIndex - 1] = Range(start: ranges[insertIndex - 1].start, end: range.end)
                        ranges.remove(at: insertIndex)
                        totalCount += 1
                        return
                    }

                    ranges[insertIndex] = Range(start: uid, end: range.end)
                    totalCount += 1
                    return
                }

                maxIndex = insertIndex
            }
        }

        let range = Range(start: uid, end: uid)
        if insertIndex < ranges.count {
            ranges.insert(range, at: insertIndex)
        } else {
            ranges.append(range)
        }
        totalCount += 1
    }

    private mutating func append(_ uid: UInt32) {
        if indexOfRange(for: uid) != nil {
            return
        }

        totalCount += 1

        if let lastIndex = ranges.indices.last {
            let range = ranges[lastIndex]

            if range.start == range.end {
                if uid == range.end + 1 || uid == range.end - 1 {
                    ranges[lastIndex] = Range(start: range.start, end: uid)
                    return
                }
            } else if range.start < range.end {
                if uid == range.end + 1 {
                    ranges[lastIndex] = Range(start: range.start, end: uid)
                    return
                }
            } else if range.start > range.end {
                if uid == range.end - 1 {
                    ranges[lastIndex] = Range(start: range.start, end: uid)
                    return
                }
            }
        }

        ranges.append(Range(start: uid, end: uid))
    }

    public mutating func add(_ uid: UniqueId) {
        precondition(uid.isValid, "Invalid unique identifier.")

        if ranges.isEmpty {
            ranges.append(Range(start: uid.id, end: uid.id))
            totalCount += 1
            return
        }

        switch sortOrder {
        case .descending:
            binaryInsertDescending(uid.id)
        case .ascending:
            binaryInsertAscending(uid.id)
        case .none:
            append(uid.id)
        }
    }

    public mutating func add(contentsOf uids: [UniqueId]) {
        for uid in uids {
            add(uid)
        }
    }

    public mutating func clear() {
        ranges.removeAll(keepingCapacity: true)
        totalCount = 0
    }

    public func contains(_ uid: UniqueId) -> Bool {
        indexOfRange(for: uid.id) != nil
    }

    public func index(of uid: UniqueId) -> Int? {
        var offset = 0
        for range in ranges {
            if range.contains(uid.id), let rangeIndex = range.index(of: uid.id) {
                return offset + rangeIndex
            }
            offset += range.count
        }
        return nil
    }

    public func uniqueId(at index: Int) -> UniqueId {
        precondition(index >= 0 && Int64(index) < totalCount, "Index out of range.")

        var offset = 0
        for range in ranges {
            if index >= offset + range.count {
                offset += range.count
                continue
            }

            let uid = range[index - offset]
            return UniqueId(validity: validity, id: uid)
        }

        preconditionFailure("Index out of range.")
    }

    public mutating func remove(at index: Int) {
        precondition(index >= 0 && Int64(index) < totalCount, "Index out of range.")

        var offset = 0
        for rangeIndex in ranges.indices {
            let range = ranges[rangeIndex]
            if index >= offset + range.count {
                offset += range.count
                continue
            }

            let uid = range[index - offset]
            remove(rangeIndex: rangeIndex, uid: uid)
            return
        }
    }

    @discardableResult
    public mutating func remove(_ uid: UniqueId) -> Bool {
        guard let rangeIndex = indexOfRange(for: uid.id) else {
            return false
        }

        remove(rangeIndex: rangeIndex, uid: uid.id)
        return true
    }

    private mutating func remove(rangeIndex: Int, uid: UInt32) {
        let range = ranges[rangeIndex]

        if uid == range.start {
            if range.start != range.end {
                if range.start <= range.end {
                    ranges[rangeIndex] = Range(start: uid + 1, end: range.end)
                } else {
                    ranges[rangeIndex] = Range(start: uid - 1, end: range.end)
                }
            } else {
                ranges.remove(at: rangeIndex)
            }
        } else if uid == range.end {
            if range.start <= range.end {
                ranges[rangeIndex] = Range(start: range.start, end: uid - 1)
            } else {
                ranges[rangeIndex] = Range(start: range.start, end: uid + 1)
            }
        } else {
            if range.start < range.end {
                ranges.insert(Range(start: range.start, end: uid - 1), at: rangeIndex)
                ranges[rangeIndex + 1] = Range(start: uid + 1, end: range.end)
            } else {
                ranges.insert(Range(start: range.start, end: uid + 1), at: rangeIndex)
                ranges[rangeIndex + 1] = Range(start: uid - 1, end: range.end)
            }
        }

        totalCount -= 1
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
        var rangeIndex = 0
        var rangeIterator: AnyIterator<UInt32>? = ranges.first?.makeIterator()

        return AnyIterator {
            while true {
                if let iterator = rangeIterator, let value = iterator.next() {
                    return UniqueId(validity: validity, id: value)
                }

                rangeIndex += 1
                guard rangeIndex < ranges.count else {
                    return nil
                }
                rangeIterator = ranges[rangeIndex].makeIterator()
            }
        }
    }

    public func serializedSubsets(maxLength: Int) throws -> [String] {
        guard maxLength >= 0 else {
            throw UniqueIdSetParseError.invalidMaxLength
        }

        var subsets: [String] = []
        var current = ""

        for range in ranges {
            let serializedRange = range.serialized()
            if !current.isEmpty {
                if current.count + 1 + serializedRange.count > maxLength {
                    subsets.append(current)
                    current = ""
                } else {
                    current.append(",")
                }
            }
            current.append(serializedRange)
        }

        subsets.append(current)
        return subsets
    }

    public var description: String {
        (try? serializedSubsets(maxLength: Int.max).first) ?? ""
    }

    public static func toString(_ uids: [UniqueId]) throws -> String {
        return try serializedSubsets(for: uids, maxLength: Int.max).first ?? ""
    }

    public static func serializedSubsets(for range: UniqueIdRange, maxLength: Int) throws -> [String] {
        guard maxLength >= 0 else {
            throw UniqueIdSetParseError.invalidMaxLength
        }
        return [range.description]
    }

    public static func serializedSubsets(for set: UniqueIdSet, maxLength: Int) throws -> [String] {
        return try set.serializedSubsets(maxLength: maxLength)
    }

    public static func serializedSubsets(for uids: [UniqueId], maxLength: Int) throws -> [String] {
        guard maxLength >= 0 else {
            throw UniqueIdSetParseError.invalidMaxLength
        }

        if uids.isEmpty {
            return [""]
        }

        var subsets: [String] = []
        var current = ""
        var index = 0

        while index < uids.count {
            let uid = uids[index]
            precondition(uid.isValid, "One or more of the uids is invalid.")

            let start = uid.id
            var end = uid.id
            var i = index + 1

            if i < uids.count {
                if uids[i].id == end + 1 {
                    end = uids[i].id
                    i += 1
                    while i < uids.count && uids[i].id == end + 1 {
                        end += 1
                        i += 1
                    }
                } else if uids[i].id == end - 1 {
                    end = uids[i].id
                    i += 1
                    while i < uids.count && uids[i].id == end - 1 {
                        end -= 1
                        i += 1
                    }
                }
            }

            let next: String
            if start != end {
                let startText = formatUid(start)
                let endText = formatUid(end)
                next = "\(startText):\(endText)"
            } else {
                next = formatUid(start)
            }

            if !current.isEmpty {
                if current.count + 1 + next.count > maxLength {
                    subsets.append(current)
                    current = ""
                } else {
                    current.append(",")
                }
            }

            current.append(next)
            index = i
        }

        subsets.append(current)
        return subsets
    }

    private static func formatUid(_ value: UInt32) -> String {
        value == UInt32.max ? "*" : String(value)
    }

    internal static func tryParse(_ token: String, validity: UInt32, minValue: inout UniqueId?, maxValue: inout UniqueId?) -> UniqueIdSet? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        var index = 0

        guard !bytes.isEmpty else {
            return nil
        }

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

        var set = UniqueIdSet(validity: validity)
        var order: SortOrder = .none
        var sorted = true
        var min = UInt32.max
        var max: UInt32 = 0
        var prev: UInt32 = 0

        while true {
            skipWhitespace(bytes, &index)
            guard let start = parseUidOrStar(bytes: bytes, index: &index) else {
                return nil
            }

            min = Swift.min(min, start)
            max = Swift.max(max, start)

            skipWhitespace(bytes, &index)
            if index < bytes.count, bytes[index] == 58 {
                index += 1
                skipWhitespace(bytes, &index)
                guard let end = parseUidOrStar(bytes: bytes, index: &index) else {
                    return nil
                }

                min = Swift.min(min, end)
                max = Swift.max(max, end)

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
                set.ranges.append(Range(start: start, end: start))
                set.totalCount += 1

                if sorted && set.ranges.count > 1 {
                    switch order {
                    case .none:
                        order = start >= prev ? .ascending : .descending
                    case .descending:
                        sorted = start <= prev
                    case .ascending:
                        sorted = start >= prev
                    }
                }

                prev = start
            }

            skipWhitespace(bytes, &index)
            if index >= bytes.count {
                break
            }

            guard bytes[index] == 44 else {
                return nil
            }
            index += 1
        }

        set.sortOrder = sorted ? order : .none

        if min <= max {
            minValue = UniqueId(validity: validity, id: min)
            maxValue = UniqueId(validity: validity, id: max)
        }

        return set
    }

    public init(parsing token: String, validity: UInt32 = 0) throws {
        var minValue: UniqueId?
        var maxValue: UniqueId?
        guard let set = Self.tryParse(token, validity: validity, minValue: &minValue, maxValue: &maxValue) else {
            throw UniqueIdSetParseError.invalidToken
        }
        self = set
    }

    private static func parseUidOrStar(bytes: [UInt8], index: inout Int) -> UInt32? {
        guard index < bytes.count else { return nil }
        if bytes[index] == 42 { // '*'
            index += 1
            return UInt32.max
        }
        return UniqueId.parseNonZeroUInt32(bytes: bytes, index: &index)
    }
}
