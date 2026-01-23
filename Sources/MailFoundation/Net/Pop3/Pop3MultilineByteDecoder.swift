//
// Pop3MultilineByteDecoder.swift
//
// POP3 multiline decoder that preserves raw bytes.
//

public enum Pop3ResponseBytesEvent: Sendable, Equatable {
    case single(Pop3Response)
    case multiline(Pop3Response, [UInt8])
}

public struct Pop3MultilineByteDecoder: Sendable {
    private var lineBuffer = ByteLineBuffer()
    private var pendingMultiline: Bool = false
    private var collectingData: Bool = false
    private var currentResponse: Pop3Response?
    private var dataLines: [[UInt8]] = []

    public init() {}

    public mutating func expectMultiline() {
        pendingMultiline = true
    }

    public mutating func append(_ bytes: [UInt8]) -> [Pop3ResponseBytesEvent] {
        let lines = lineBuffer.append(bytes)
        var events: [Pop3ResponseBytesEvent] = []

        for line in lines {
            if collectingData {
                if line == [0x2e] {
                    if let response = currentResponse {
                        let data = assembleBytes(from: dataLines)
                        events.append(.multiline(response, data))
                    }
                    resetMultiline()
                } else {
                    if line.count >= 2, line[0] == 0x2e, line[1] == 0x2e {
                        dataLines.append(Array(line.dropFirst()))
                    } else {
                        dataLines.append(line)
                    }
                }
                continue
            }

            if pendingMultiline {
                let text = String(decoding: line, as: UTF8.self)
                if let response = Pop3Response.parse(text) {
                    if response.status == .ok {
                        currentResponse = response
                        collectingData = true
                    } else {
                        events.append(.single(response))
                        pendingMultiline = false
                    }
                }
                continue
            }

            let text = String(decoding: line, as: UTF8.self)
            if let response = Pop3Response.parse(text) {
                events.append(.single(response))
            }
        }

        return events
    }

    private mutating func resetMultiline() {
        pendingMultiline = false
        collectingData = false
        currentResponse = nil
        dataLines.removeAll(keepingCapacity: true)
    }

    private func assembleBytes(from lines: [[UInt8]]) -> [UInt8] {
        guard !lines.isEmpty else { return [] }
        var data: [UInt8] = []
        data.reserveCapacity(lines.reduce(0) { $0 + $1.count + 2 })
        for (index, line) in lines.enumerated() {
            if index > 0 {
                data.append(0x0D)
                data.append(0x0A)
            }
            data.append(contentsOf: line)
        }
        return data
    }
}
