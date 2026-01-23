//
// ByteLineBuffer.swift
//
// Incremental CRLF line buffering for raw bytes.
//

public struct ByteLineBuffer: Sendable {
    private var buffer: [UInt8]

    public init(capacity: Int = 0) {
        self.buffer = []
        if capacity > 0 {
            buffer.reserveCapacity(capacity)
        }
    }

    public mutating func append(_ bytes: [UInt8]) -> [[UInt8]] {
        guard !bytes.isEmpty else { return [] }
        buffer.append(contentsOf: bytes)
        return drainLines()
    }

    private mutating func drainLines() -> [[UInt8]] {
        var lines: [[UInt8]] = []
        var start = 0
        var index = 0

        while index < buffer.count {
            if buffer[index] == 0x0A {
                var end = index
                if end > start, buffer[end - 1] == 0x0D {
                    end -= 1
                }
                let line = Array(buffer[start..<end])
                lines.append(line)
                index += 1
                start = index
            } else {
                index += 1
            }
        }

        if start > 0 {
            buffer.removeFirst(start)
        }

        return lines
    }
}
