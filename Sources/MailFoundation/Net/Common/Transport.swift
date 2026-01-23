//
// Transport.swift
//
// Simple transport abstraction.
//

import Foundation

public protocol Transport: AnyObject {
    func open()
    func close()
    func write(_ bytes: [UInt8]) -> Int
    func readAvailable(maxLength: Int) -> [UInt8]
}

public protocol StartTlsTransport: Transport {
    func startTLS(validateCertificate: Bool)
}

public final class StreamTransport: Transport {
    private let input: InputStream
    private let output: OutputStream
    private let bufferSize: Int
    private var isOpen = false

    public init(input: InputStream, output: OutputStream, bufferSize: Int = 4096) {
        self.input = input
        self.output = output
        self.bufferSize = max(1, bufferSize)
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        input.open()
        output.open()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        input.close()
        output.close()
    }

    public func write(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var totalWritten = 0
        while totalWritten < bytes.count {
            let written = bytes.withUnsafeBytes { pointer -> Int in
                guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                let start = base.advanced(by: totalWritten)
                return output.write(start, maxLength: bytes.count - totalWritten)
            }

            if written <= 0 {
                break
            }
            totalWritten += written
        }
        return totalWritten
    }

    public func readAvailable(maxLength: Int = 4096) -> [UInt8] {
        guard input.hasBytesAvailable else { return [] }
        var buffer = Array(repeating: UInt8(0), count: max(1, maxLength))
        let count = input.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { return [] }
        return Array(buffer.prefix(count))
    }
}
