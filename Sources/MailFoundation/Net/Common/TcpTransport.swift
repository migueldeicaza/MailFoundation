//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

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
    private var scramChannelBindingCache: ScramChannelBinding?

    public var scramChannelBinding: ScramChannelBinding? {
        if let cached = scramChannelBindingCache {
            return cached
        }
        guard let output else { return nil }
        if let binding = TlsChannelBindingHelper.tlsServerEndPoint(from: output) {
            scramChannelBindingCache = binding
            return binding
        }
        return nil
    }

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
        scramChannelBindingCache = nil
    }

    public var isConnected: Bool {
        updateConnectionStateFromStreams()
        return isOpen
    }

    public func write(_ bytes: [UInt8]) -> Int {
        guard let output, !bytes.isEmpty else { return 0 }
        updateConnectionStateFromStreams()
        guard isOpen else { return 0 }

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
                updateConnectionStateFromStreams()
                break
            }
            totalWritten += written
        }
        return totalWritten
    }

    public func readAvailable(maxLength: Int) -> [UInt8] {
        updateConnectionStateFromStreams()
        guard isOpen, let input else { return [] }
        guard input.hasBytesAvailable else {
            updateConnectionStateFromStreams()
            return []
        }

        var buffer = Array(repeating: UInt8(0), count: max(1, maxLength))
        let count = input.read(&buffer, maxLength: buffer.count)
        if count <= 0 {
            updateConnectionStateFromStreams()
            if count == 0 {
                isOpen = false
            }
            return []
        }
        return Array(buffer.prefix(count))
    }

    public func startTLS(validateCertificate: Bool) {
        mode = .tls(validateCertificate: validateCertificate)
        if let input, let output {
            configureTLS(input: input, output: output)
        }
        scramChannelBindingCache = nil
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

    private func updateConnectionStateFromStreams() {
        guard isOpen else { return }
        if let input, isTerminal(status: input.streamStatus) {
            isOpen = false
            return
        }
        if let output, isTerminal(status: output.streamStatus) {
            isOpen = false
        }
    }

    private func isTerminal(status: Stream.Status) -> Bool {
        switch status {
        case .atEnd, .closed, .error:
            return true
        default:
            return false
        }
    }
}
