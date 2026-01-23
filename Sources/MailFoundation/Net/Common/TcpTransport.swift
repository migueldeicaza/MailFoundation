//
// TcpTransport.swift
//
// Synchronous TCP/TLS transport using Foundation streams.
//

import Foundation

public final class TcpTransport: StartTlsTransport {
    public enum Mode: Sendable {
        case tcp
        case tls(validateCertificate: Bool)
    }

    private let host: String
    private let port: Int
    private var mode: Mode
    private let bufferSize: Int
    private var input: InputStream?
    private var output: OutputStream?
    private var isOpen = false

    public init(host: String, port: Int, mode: Mode = .tcp, bufferSize: Int = 4096) {
        self.host = host
        self.port = port
        self.mode = mode
        self.bufferSize = max(1, bufferSize)
    }

    public func open() {
        guard !isOpen else { return }
        if input == nil || output == nil {
            Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
        }

        if let input, let output {
            configureTLS(input: input, output: output)
            input.open()
            output.open()
            isOpen = true
        }
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        input?.close()
        output?.close()
    }

    public func write(_ bytes: [UInt8]) -> Int {
        guard let output, !bytes.isEmpty else { return 0 }
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

    public func readAvailable(maxLength: Int) -> [UInt8] {
        guard let input, input.hasBytesAvailable else { return [] }
        var buffer = Array(repeating: UInt8(0), count: max(1, maxLength))
        let count = input.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { return [] }
        return Array(buffer.prefix(count))
    }

    public func startTLS(validateCertificate: Bool) {
        mode = .tls(validateCertificate: validateCertificate)
        if let input, let output {
            configureTLS(input: input, output: output)
        }
    }

    private func configureTLS(input: InputStream, output: OutputStream) {
        guard case let .tls(validateCertificate) = mode else { return }
        let settings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: validateCertificate
        ]
        let key = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        _ = input.setProperty(settings, forKey: key)
        _ = output.setProperty(settings, forKey: key)
    }
}
