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
// Transport.swift
//
// Simple transport abstraction.
//

import Foundation

// MARK: - Transport Protocol

/// A protocol defining low-level network transport operations.
///
/// `Transport` provides a simple abstraction over network connections,
/// supporting basic open, close, read, and write operations. It is used
/// by mail service implementations to communicate with servers.
///
/// ## Implementations
///
/// - ``StreamTransport``: Built on Foundation `InputStream`/`OutputStream`
/// - ``TcpTransport``: Direct TCP socket implementation
/// - ``PosixSocketTransport``: POSIX socket-based implementation
///
/// ## Usage Pattern
///
/// ```swift
/// let transport: Transport = StreamTransport(input: inputStream, output: outputStream)
/// transport.open()
/// defer { transport.close() }
///
/// let written = transport.write(Array("EHLO example.com\r\n".utf8))
/// let response = transport.readAvailable(maxLength: 4096)
/// ```
public protocol Transport: AnyObject {
    /// Opens the transport connection.
    ///
    /// Call this method before performing any read or write operations.
    /// It is safe to call this method multiple times; subsequent calls
    /// have no effect if the transport is already open.
    func open()

    /// Closes the transport connection.
    ///
    /// After closing, the transport cannot be used for further operations.
    /// It is safe to call this method multiple times.
    func close()

    /// Whether the transport connection is currently alive.
    ///
    /// Implementations should return `false` once the underlying connection has
    /// been closed by either peer or entered an unrecoverable error state.
    var isConnected: Bool { get }

    /// Writes data to the transport.
    ///
    /// This method attempts to write all provided bytes to the transport.
    /// It may block until all data is written or an error occurs.
    ///
    /// - Parameter bytes: The data to write.
    /// - Returns: The number of bytes actually written, which may be less
    ///   than the input length if an error occurred.
    func write(_ bytes: [UInt8]) -> Int

    /// Reads available data from the transport.
    ///
    /// This method returns immediately with whatever data is available,
    /// up to the specified maximum length. If no data is available,
    /// it returns an empty array.
    ///
    /// - Parameter maxLength: The maximum number of bytes to read.
    /// - Returns: The data read, or an empty array if no data is available.
    func readAvailable(maxLength: Int) -> [UInt8]
}

public extension Transport {
    var isConnected: Bool { true }
}

// MARK: - StartTlsTransport Protocol

/// A transport that supports upgrading to TLS encryption.
///
/// `StartTlsTransport` extends ``Transport`` with the ability to upgrade
/// an unencrypted connection to TLS, as required by the STARTTLS command
/// in SMTP, POP3, and IMAP protocols.
///
/// ## STARTTLS Flow
///
/// 1. Connect to server on standard port
/// 2. Perform initial protocol handshake
/// 3. Send STARTTLS command
/// 4. Call ``startTLS(validateCertificate:)``
/// 5. Continue with encrypted communication
public protocol StartTlsTransport: Transport {
    /// Optional channel binding data for SCRAM-PLUS authentication.
    ///
    /// Transports that can access TLS session details should expose a
    /// ``ScramChannelBinding`` (typically `tls-server-end-point`).
    var scramChannelBinding: ScramChannelBinding? { get }

    /// Upgrades the connection to use TLS encryption.
    ///
    /// This method performs the TLS handshake and upgrades the
    /// connection to encrypted mode. After this call completes
    /// successfully, all subsequent reads and writes are encrypted.
    ///
    /// - Parameter validateCertificate: If `true`, validates the server's
    ///   certificate against trusted roots. Set to `false` only for
    ///   testing with self-signed certificates.
    ///
    /// - Warning: Disabling certificate validation exposes the connection
    ///   to man-in-the-middle attacks.
    func startTLS(validateCertificate: Bool)
}

// MARK: - CompressionTransport Protocol

/// A transport that supports enabling IMAP COMPRESS.
///
/// IMAP compression is negotiated at the protocol level and then the transport
/// begins compressing subsequent reads and writes.
public protocol CompressionTransport: Transport {
    /// Enables compression for subsequent reads and writes.
    ///
    /// - Parameter algorithm: The negotiated compression algorithm (e.g., "DEFLATE").
    func startCompression(algorithm: String) throws
}

// MARK: - StreamTransport

/// A transport implementation based on Foundation streams.
///
/// `StreamTransport` wraps `InputStream` and `OutputStream` to provide
/// a ``Transport`` interface. It is useful when you already have Foundation
/// streams available, such as from `Stream.getStreamsToHost()`.
///
/// ## Example Usage
///
/// ```swift
/// var inputStream: InputStream?
/// var outputStream: OutputStream?
/// Stream.getStreamsToHost(withName: "mail.example.com", port: 25,
///                         inputStream: &inputStream, outputStream: &outputStream)
///
/// guard let input = inputStream, let output = outputStream else {
///     throw ConnectionError.failed
/// }
///
/// let transport = StreamTransport(input: input, output: output)
/// transport.open()
/// ```
///
/// ## Thread Safety
///
/// This class is not thread-safe. Access from multiple threads must be
/// externally synchronized.
public final class StreamTransport: Transport {
    /// The input stream for reading data.
    private let input: InputStream

    /// The output stream for writing data.
    private let output: OutputStream

    /// The buffer size for read operations.
    private let bufferSize: Int

    /// Whether the transport is currently open.
    private var isOpen = false

    /// Creates a stream transport with the specified streams.
    ///
    /// - Parameters:
    ///   - input: The input stream for receiving data.
    ///   - output: The output stream for sending data.
    ///   - bufferSize: The buffer size for read operations (default: 4096).
    public init(input: InputStream, output: OutputStream, bufferSize: Int = 4096) {
        self.input = input
        self.output = output
        self.bufferSize = max(1, bufferSize)
    }

    /// Opens the underlying streams.
    ///
    /// Both input and output streams are opened. If already open,
    /// this method has no effect.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        input.open()
        output.open()
    }

    /// Closes the underlying streams.
    ///
    /// Both input and output streams are closed. If already closed,
    /// this method has no effect.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        input.close()
        output.close()
    }

    public var isConnected: Bool {
        updateConnectionStateFromStreams()
        return isOpen
    }

    /// Writes data to the output stream.
    ///
    /// This method attempts to write all provided bytes, looping
    /// until all data is written or an error occurs.
    ///
    /// - Parameter bytes: The data to write.
    /// - Returns: The total number of bytes written.
    public func write(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
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

    /// Reads available data from the input stream.
    ///
    /// Returns immediately with whatever data is currently available.
    ///
    /// - Parameter maxLength: The maximum number of bytes to read (default: 4096).
    /// - Returns: The data read, or an empty array if no data is available.
    public func readAvailable(maxLength: Int = 4096) -> [UInt8] {
        updateConnectionStateFromStreams()
        guard isOpen else { return [] }
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

    private func updateConnectionStateFromStreams() {
        guard isOpen else { return }
        if isTerminal(status: input.streamStatus) || isTerminal(status: output.streamStatus) {
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
