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
// NetworkTransport.swift
//
// Foundation stream transport (iOS/macOS) with in-place STARTTLS.
//

#if canImport(Network)
import Foundation

@available(macOS 10.15, iOS 13.0, *)
public actor NetworkTransport: AsyncStartTlsTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation

    private let host: String
    private let port: Int
    private var input: InputStream?
    private var output: OutputStream?
    private var started: Bool = false
    private var readerTask: Task<Void, Never>?
    private var scramChannelBindingCache: ScramChannelBinding?

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = Int(port)
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    public var scramChannelBinding: ScramChannelBinding? {
        get async {
            if let cached = scramChannelBindingCache {
                return cached
            }
            guard let output else {
                return nil
            }
            if let binding = TlsChannelBindingHelper.tlsServerEndPoint(from: output) {
                scramChannelBindingCache = binding
            }
            return scramChannelBindingCache
        }
    }

    public func start() async throws {
        guard !started else { return }
        started = true

        if input == nil || output == nil {
            Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
        }

        guard let input, let output else {
            started = false
            throw AsyncTransportError.connectionFailed
        }

        input.open()
        output.open()
        readerTask = Task { await readLoop() }
    }

    /// Starts the transport with implicit TLS enabled (for IMAPS/SMTPS on port 993/465).
    ///
    /// This method sets up TLS before opening the streams, which is required for
    /// implicit TLS connections where encryption starts immediately.
    ///
    /// - Parameter validateCertificate: Whether to validate the server certificate.
    public func startSecure(validateCertificate: Bool = true) async throws {
        guard !started else { return }
        started = true

        if input == nil || output == nil {
            Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
        }

        guard let input, let output else {
            started = false
            throw AsyncTransportError.connectionFailed
        }

        // Set SSL properties BEFORE opening streams for implicit TLS
        let settings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: validateCertificate
        ]
        let key = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        let inputOk = input.setProperty(settings, forKey: key)
        let outputOk = output.setProperty(settings, forKey: key)
        guard inputOk && outputOk else {
            started = false
            throw AsyncTransportError.connectionFailed
        }

        input.open()
        output.open()
        readerTask = Task { await readLoop() }
    }

    public func stop() async {
        guard started else { return }
        started = false
        readerTask?.cancel()
        readerTask = nil
        input?.close()
        output?.close()
        scramChannelBindingCache = nil
        continuation.finish()
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        guard let output else {
            throw AsyncTransportError.connectionFailed
        }
        guard !bytes.isEmpty else { return }

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
                throw AsyncTransportError.sendFailed
            }

            totalWritten += written
        }
    }

    public func startTLS(validateCertificate: Bool) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        guard let input, let output else {
            throw AsyncTransportError.connectionFailed
        }

        let settings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: validateCertificate
        ]
        let key = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        let inputOk = input.setProperty(settings, forKey: key)
        let outputOk = output.setProperty(settings, forKey: key)
        guard inputOk && outputOk else {
            throw AsyncTransportError.connectionFailed
        }
        scramChannelBindingCache = nil
    }

    private func readLoop() async {
        guard let input else { return }
        var buffer = Array(repeating: UInt8(0), count: 4096)

        while started {
            if !input.hasBytesAvailable {
                if input.streamStatus == .atEnd {
                    await stop()
                    break
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
                continue
            }

            let count = input.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                continuation.yield(Array(buffer.prefix(count)))
            } else if count == 0 {
                await stop()
                break
            } else {
                await stop()
                break
            }
        }
    }
}
#endif
