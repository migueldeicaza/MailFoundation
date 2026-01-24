//
// SocketTransport.swift
//
// POSIX socket transport for non-iOS platforms.
//

#if !os(iOS)
import Foundation

#if canImport(Security)
@available(macOS 10.15, iOS 13.0, *)
public actor SocketTransport: AsyncStartTlsTransport {
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
#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@available(macOS 10.15, iOS 13.0, *)
public actor SocketTransport: AsyncTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var socketFD: Int32 = -1
    private var started: Bool = false
    private var readerTask: Task<Void, Never>?

    private let host: String
    private let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    public func start() async throws {
        guard !started else { return }
        started = true
        socketFD = try openSocket()
        readerTask = Task { await readLoop() }
    }

    public func stop() async {
        guard started else { return }
        started = false
        if socketFD >= 0 {
            _ = close(socketFD)
            socketFD = -1
        }
        readerTask?.cancel()
        readerTask = nil
        continuation.finish()
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard started, socketFD >= 0 else {
            throw AsyncTransportError.notStarted
        }

        var total = 0
        while total < bytes.count {
            let written = bytes.withUnsafeBytes { pointer -> Int in
                guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                #if canImport(Darwin)
                return Darwin.write(socketFD, base.advanced(by: total), bytes.count - total)
                #else
                return Glibc.write(socketFD, base.advanced(by: total), bytes.count - total)
                #endif
            }

            if written <= 0 {
                throw AsyncTransportError.sendFailed
            }
            total += written
        }
    }

    private func readLoop() async {
        var buffer = Array(repeating: UInt8(0), count: 4096)
        let bufferSize = buffer.count
        while started, socketFD >= 0 {
            let count = buffer.withUnsafeMutableBytes { pointer -> Int in
                guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                #if canImport(Darwin)
                return Darwin.read(socketFD, base, bufferSize)
                #else
                return Glibc.read(socketFD, base, bufferSize)
                #endif
            }

            if count > 0 {
                let chunk = Array(buffer.prefix(count))
                continuation.yield(chunk)
            } else {
                await stop()
                break
            }

            if Task.isCancelled {
                break
            }
        }
    }

    private func openSocket() throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var infoPointer: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let status = getaddrinfo(host, portString, &hints, &infoPointer)
        guard status == 0, let firstInfo = infoPointer else {
            throw AsyncTransportError.connectionFailed
        }

        defer {
            freeaddrinfo(infoPointer)
        }

        var pointer: UnsafeMutablePointer<addrinfo>? = firstInfo
        while let info = pointer {
            let socketFD = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketFD < 0 {
                pointer = info.pointee.ai_next
                continue
            }

            if connect(socketFD, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                return socketFD
            }

            _ = close(socketFD)
            pointer = info.pointee.ai_next
        }

        throw AsyncTransportError.connectionFailed
    }
}
#endif
#endif
