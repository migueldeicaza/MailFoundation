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

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = Int(port)
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
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

    public func stop() async {
        guard started else { return }
        started = false
        readerTask?.cancel()
        readerTask = nil
        input?.close()
        output?.close()
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
