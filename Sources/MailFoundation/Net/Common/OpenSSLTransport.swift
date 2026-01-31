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
// OpenSSLTransport.swift
//
// OpenSSL-based transport with STARTTLS support for Linux and macOS.
//

#if canImport(COpenSSL)
import COpenSSL
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum OpenSSLTransportError: Error, Sendable {
    case sslContextCreationFailed
    case sslCreationFailed
    case sslHandshakeFailed(String)
    case certificateValidationFailed(String)
}

@available(macOS 10.15, iOS 13.0, *)
public actor OpenSSLTransport: AsyncStartTlsTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation

    private let host: String
    private let port: UInt16
    private var socketFD: Int32 = -1
    private var started: Bool = false
    private var readerTask: Task<Void, Never>?

    private var sslContext: OpaquePointer?
    private var ssl: OpaquePointer?
    private var tlsEnabled: Bool = false
    private var scramChannelBindingCache: ScramChannelBinding?

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    public var scramChannelBinding: ScramChannelBinding? {
        get async {
            scramChannelBindingCache
        }
    }

    public func start() async throws {
        guard !started else { return }
        started = true
        socketFD = try openSocket()
        readerTask = Task { await readLoop() }
    }

    /// Starts the transport with implicit TLS enabled (for IMAPS/SMTPS on port 993/465).
    ///
    /// This method establishes the socket connection and performs the TLS
    /// handshake before any reads occur.
    ///
    /// - Parameter validateCertificate: Whether to validate the server certificate.
    public func startSecure(validateCertificate: Bool = true) async throws {
        guard !started else { return }
        started = true

        do {
            socketFD = try openSocket()
            try await startTLS(validateCertificate: validateCertificate)
        } catch {
            await stop()
            throw error
        }

        readerTask = Task { await readLoop() }
    }

    public func stop() async {
        guard started else { return }
        started = false

        cleanupSSL()

        if socketFD >= 0 {
            #if canImport(Darwin)
            _ = Darwin.close(socketFD)
            #else
            _ = Glibc.close(socketFD)
            #endif
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

        if tlsEnabled {
            try await sendSSL(bytes)
        } else {
            try await sendPlain(bytes)
        }
    }

    public func startTLS(validateCertificate: Bool) async throws {
        guard started, socketFD >= 0 else {
            throw AsyncTransportError.notStarted
        }

        // Create SSL context
        guard let ctx = SSL_CTX_new(TLS_client_method()) else {
            throw OpenSSLTransportError.sslContextCreationFailed
        }
        sslContext = ctx

        // Configure certificate validation
        if validateCertificate {
            SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, nil)
            SSL_CTX_set_default_verify_paths(ctx)
        } else {
            SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nil)
        }

        // Create SSL object
        guard let sslObj = SSL_new(ctx) else {
            throw OpenSSLTransportError.sslCreationFailed
        }
        ssl = sslObj

        // Set SNI hostname
        // SSL_set_tlsext_host_name is a macro, so we call SSL_ctrl directly
        // SSL_CTRL_SET_TLSEXT_HOSTNAME = 55, TLSEXT_NAMETYPE_host_name = 0
        _ = host.withCString { hostname in
            SSL_ctrl(sslObj, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, UnsafeMutableRawPointer(mutating: hostname))
        }

        // Configure hostname verification
        if validateCertificate {
            let param = SSL_get0_param(sslObj)
            _ = host.withCString { hostname in
                X509_VERIFY_PARAM_set1_host(param, hostname, 0)
            }
        }

        // Attach socket to SSL
        SSL_set_fd(sslObj, socketFD)

        // Clear any stale errors before handshake
        while ERR_get_error() != 0 {}

        // Perform handshake with retry for non-blocking socket
        var handshakeComplete = false
        var attempts = 0
        let maxAttempts = 100 // Prevent infinite loop
        while !handshakeComplete && attempts < maxAttempts {
            attempts += 1
            let result = SSL_connect(sslObj)
            if result == 1 {
                handshakeComplete = true
            } else {
                let errorCode = SSL_get_error(sslObj, result)
                if errorCode == SSL_ERROR_WANT_READ {
                    // Wait for socket to be readable
                    if !pollForReadWithTimeout(milliseconds: 100) {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    continue
                } else if errorCode == SSL_ERROR_WANT_WRITE {
                    // Wait for socket to be writable
                    if !pollForWriteWithTimeout(milliseconds: 100) {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    continue
                }
                let errorMessage = getSSLErrorMessage(errorCode)
                throw OpenSSLTransportError.sslHandshakeFailed(errorMessage)
            }
        }

        if !handshakeComplete {
            throw OpenSSLTransportError.sslHandshakeFailed("Handshake timeout after \(maxAttempts) attempts")
        }

        // Verify certificate if requested
        if validateCertificate {
            let verifyResult = SSL_get_verify_result(sslObj)
            if verifyResult != X509_V_OK {
                throw OpenSSLTransportError.certificateValidationFailed(
                    "Certificate verification failed with code: \(verifyResult)"
                )
            }
        }

        scramChannelBindingCache = buildScramChannelBinding(from: sslObj)
        tlsEnabled = true
    }

    // MARK: - Private Methods

    private func sendPlain(_ bytes: [UInt8]) async throws {
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

            if written < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    try await Task.sleep(nanoseconds: 5_000_000)
                    continue
                }
                throw AsyncTransportError.sendFailed
            }
            if written == 0 {
                throw AsyncTransportError.sendFailed
            }
            total += written
        }
    }

    private func sendSSL(_ bytes: [UInt8]) async throws {
        guard let sslObj = ssl else {
            throw AsyncTransportError.sendFailed
        }

        var total = 0
        while total < bytes.count {
            let written = bytes.withUnsafeBytes { pointer -> Int32 in
                guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                return SSL_write(sslObj, base.advanced(by: total), Int32(bytes.count - total))
            }

            if written <= 0 {
                let err = SSL_get_error(sslObj, written)
                if err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE {
                    try await Task.sleep(nanoseconds: 5_000_000)
                    continue
                }
                throw AsyncTransportError.sendFailed
            }
            total += Int(written)
        }
    }

    private func readLoop() async {
        var buffer = Array(repeating: UInt8(0), count: 4096)
        let bufferSize = buffer.count

        while started, socketFD >= 0 {
            // Poll for data availability to avoid blocking the cooperative thread pool
            if !pollForRead() {
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                continue
            }

            let count: Int

            if tlsEnabled, let sslObj = ssl {
                count = buffer.withUnsafeMutableBytes { pointer -> Int in
                    guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    return Int(SSL_read(sslObj, base, Int32(bufferSize)))
                }

                // Handle SSL_ERROR_WANT_READ/WRITE for non-blocking SSL
                if count <= 0 {
                    let err = SSL_get_error(sslObj, Int32(count))
                    if err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE {
                        try? await Task.sleep(nanoseconds: 5_000_000)
                        continue
                    }
                }
            } else {
                count = buffer.withUnsafeMutableBytes { pointer -> Int in
                    guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    #if canImport(Darwin)
                    return Darwin.read(socketFD, base, bufferSize)
                    #else
                    return Glibc.read(socketFD, base, bufferSize)
                    #endif
                }

                // Handle EAGAIN/EWOULDBLOCK for non-blocking socket
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    continue
                }
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

    private func pollForRead() -> Bool {
        pollForReadWithTimeout(milliseconds: 0)
    }

    private func pollForReadWithTimeout(milliseconds: Int32) -> Bool {
        let fd = socketFD
        #if canImport(Darwin)
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let result = Darwin.poll(&pfd, 1, milliseconds)
        return result > 0 && (pfd.revents & Int16(POLLIN)) != 0
        #else
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let result = Glibc.poll(&pfd, 1, milliseconds)
        return result > 0 && (pfd.revents & Int16(POLLIN)) != 0
        #endif
    }

    private func pollForWriteWithTimeout(milliseconds: Int32) -> Bool {
        let fd = socketFD
        #if canImport(Darwin)
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let result = Darwin.poll(&pfd, 1, milliseconds)
        return result > 0 && (pfd.revents & Int16(POLLOUT)) != 0
        #else
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let result = Glibc.poll(&pfd, 1, milliseconds)
        return result > 0 && (pfd.revents & Int16(POLLOUT)) != 0
        #endif
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
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd < 0 {
                pointer = info.pointee.ai_next
                continue
            }

            #if canImport(Darwin)
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            #endif

            if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                // Set non-blocking mode after connection
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                return fd
            }

            #if canImport(Darwin)
            _ = Darwin.close(fd)
            #else
            _ = Glibc.close(fd)
            #endif
            pointer = info.pointee.ai_next
        }

        throw AsyncTransportError.connectionFailed
    }

    private func cleanupSSL() {
        if let sslObj = ssl {
            SSL_shutdown(sslObj)
            SSL_free(sslObj)
            ssl = nil
        }
        if let ctx = sslContext {
            SSL_CTX_free(ctx)
            sslContext = nil
        }
        tlsEnabled = false
        scramChannelBindingCache = nil
    }

    private func buildScramChannelBinding(from sslObj: OpaquePointer) -> ScramChannelBinding? {
        // OpenSSL 3.0 renamed SSL_get_peer_certificate to SSL_get1_peer_certificate
        guard let cert = SSL_get1_peer_certificate(sslObj) else {
            return nil
        }
        defer { X509_free(cert) }
        guard let certData = derEncodedCertificate(cert) else {
            return nil
        }
        let digest = sha256(certData)
        return ScramChannelBinding.tlsServerEndPoint(digest)
    }

    private func derEncodedCertificate(_ cert: OpaquePointer) -> Data? {
        var buffer: UnsafeMutablePointer<UInt8>?
        let length = i2d_X509(cert, &buffer)
        guard length > 0, let buffer else {
            return nil
        }
        // OPENSSL_free is a macro; use CRYPTO_free directly for OpenSSL 3.0
        defer { CRYPTO_free(buffer, nil, 0) }
        return Data(bytes: buffer, count: Int(length))
    }

    private func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            _ = SHA256(base, data.count, &digest)
        }
        return Data(digest)
    }

    private func getSSLErrorMessage(_ errorCode: Int32) -> String {
        var message: String
        switch errorCode {
        case SSL_ERROR_NONE:
            message = "No error"
        case SSL_ERROR_SSL:
            message = "SSL library error"
        case SSL_ERROR_WANT_READ:
            message = "Want read"
        case SSL_ERROR_WANT_WRITE:
            message = "Want write"
        case SSL_ERROR_SYSCALL:
            message = "System call error (errno: \(errno))"
        case SSL_ERROR_ZERO_RETURN:
            message = "Connection closed"
        case SSL_ERROR_WANT_CONNECT:
            message = "Want connect"
        case SSL_ERROR_WANT_ACCEPT:
            message = "Want accept"
        default:
            message = "Unknown error: \(errorCode)"
        }

        // Get detailed error from OpenSSL error queue
        var errCode = ERR_get_error()
        while errCode != 0 {
            var buf = [CChar](repeating: 0, count: 256)
            ERR_error_string_n(errCode, &buf, buf.count)
            let errStr = buf.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
            message += "; \(errStr)"
            errCode = ERR_get_error()
        }

        return message
    }
}
#endif
