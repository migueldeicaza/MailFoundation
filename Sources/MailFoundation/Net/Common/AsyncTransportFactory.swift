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
// AsyncTransportFactory.swift
//
// Async transport factory helpers.
//

// MARK: - Async Transport Backend

/// Specifies the underlying implementation for asynchronous transports.
///
/// Different backends provide different capabilities and platform support.
/// Choose the backend appropriate for your deployment target and requirements.
public enum AsyncTransportBackend: Sendable {
    /// Network framework-based transport (Apple platforms).
    ///
    /// This is the recommended backend for Apple platforms as it
    /// integrates well with the system's networking stack and
    /// provides modern features like connection monitoring.
    ///
    /// - Note: Available on platforms that support the Network framework.
    case network

    /// POSIX socket-based transport.
    ///
    /// This provides lower-level socket access using POSIX APIs.
    /// It may be useful for cross-platform code or when Network
    /// framework features are not needed.
    ///
    /// - Note: Not available on iOS.
    case socket

    /// In-memory stream transport for testing.
    ///
    /// This backend does not make actual network connections and is
    /// useful for unit testing mail service implementations.
    case asyncStream

    /// OpenSSL-based transport.
    ///
    /// This backend uses OpenSSL for TLS and may be useful when
    /// the platform's native TLS implementation is not suitable.
    ///
    /// - Note: Requires the `COpenSSL` package. On Linux this is enabled by default.
    ///   On macOS, enable package trait `OpenSSL` to make this backend available.
    case openssl
}

// MARK: - Async Transport Factory Error

/// Errors that can occur when creating async transports.
public enum AsyncTransportFactoryError: Error, Sendable {
    /// The requested backend is not available on this platform.
    ///
    /// This occurs when attempting to use a backend that requires
    /// platform features or libraries that are not present.
    case backendUnavailable
}

// MARK: - Async Transport Factory

/// A factory for creating asynchronous transport instances.
///
/// `AsyncTransportFactory` provides convenient methods for creating
/// ``AsyncTransport`` instances with optional proxy support. It handles
/// backend selection and proxy negotiation automatically.
///
/// ## Basic Usage
///
/// ```swift
/// // Create a transport using Network framework
/// let transport = try AsyncTransportFactory.make(
///     host: "smtp.example.com",
///     port: 587,
///     backend: .network
/// )
/// try await transport.start()
/// ```
///
/// ## With Proxy Support
///
/// ```swift
/// // Create a transport through a SOCKS5 proxy
/// let proxy = ProxySettings(
///     host: "proxy.example.com",
///     port: 1080,
///     type: .socks5,
///     username: "user",
///     password: "pass"
/// )
///
/// let transport = try await AsyncTransportFactory.make(
///     host: "imap.example.com",
///     port: 993,
///     backend: .network,
///     proxy: proxy
/// )
/// // Transport is connected through the proxy
/// ```
///
/// - Note: Available on macOS 10.15+ and iOS 13.0+.
@available(macOS 10.15, iOS 13.0, *)
public enum AsyncTransportFactory {
    /// Creates an async transport to the specified host.
    ///
    /// This is the simple factory method for creating transports
    /// without proxy support.
    ///
    /// - Parameters:
    ///   - host: The target host to connect to.
    ///   - port: The target port to connect to.
    ///   - backend: The transport backend to use.
    /// - Returns: A new transport instance (not yet started).
    /// - Throws: ``AsyncTransportFactoryError/backendUnavailable`` if the
    ///   requested backend is not available.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let transport = try AsyncTransportFactory.make(
    ///     host: "mail.example.com",
    ///     port: 993,
    ///     backend: .network
    /// )
    /// try await transport.start()
    /// defer { Task { await transport.stop() } }
    /// ```
    public static func make(host: String, port: UInt16, backend: AsyncTransportBackend) throws -> AsyncTransport {
        switch backend {
        case .network:
            #if canImport(Network)
            return NetworkTransport(host: host, port: port)
            #else
            throw AsyncTransportFactoryError.backendUnavailable
            #endif
        case .socket:
            #if !os(iOS)
            return SocketTransport(host: host, port: port)
            #else
            throw AsyncTransportFactoryError.backendUnavailable
            #endif
        case .asyncStream:
            return AsyncStreamTransport()
        case .openssl:
            #if canImport(COpenSSL)
            return OpenSSLTransport(host: host, port: port)
            #else
            throw AsyncTransportFactoryError.backendUnavailable
            #endif
        }
    }

    /// Creates an async transport with optional proxy support.
    ///
    /// This method creates a transport and optionally routes it through
    /// a proxy server. When proxy settings are provided, the method
    /// handles the proxy negotiation automatically and returns a
    /// transport that is already connected through the proxy.
    ///
    /// - Parameters:
    ///   - host: The target host to connect to.
    ///   - port: The target port to connect to.
    ///   - backend: The transport backend to use.
    ///   - proxy: Optional proxy settings for tunneled connections.
    /// - Returns: A transport connected to the target (possibly through a proxy).
    /// - Throws: ``AsyncTransportFactoryError/backendUnavailable`` if the
    ///   backend is not available, or ``ProxyError`` if proxy negotiation fails.
    ///
    /// ## Proxy Support
    ///
    /// When proxy settings are provided:
    /// 1. A transport is created to the proxy server
    /// 2. The transport is started
    /// 3. Proxy negotiation is performed
    /// 4. The tunneled transport is returned
    ///
    /// If any bytes are received after proxy negotiation (common with some
    /// proxies), they are buffered and returned first when reading from
    /// the transport.
    ///
    /// ## Example with SOCKS5 Proxy
    ///
    /// ```swift
    /// let proxy = ProxySettings(
    ///     host: "socks.example.com",
    ///     port: 1080,
    ///     type: .socks5
    /// )
    ///
    /// let transport = try await AsyncTransportFactory.make(
    ///     host: "imap.example.com",
    ///     port: 993,
    ///     backend: .network,
    ///     proxy: proxy
    /// )
    /// // Transport is ready for TLS and mail protocol
    /// ```
    public static func make(
        host: String,
        port: UInt16,
        backend: AsyncTransportBackend,
        proxy: ProxySettings?
    ) async throws -> AsyncTransport {
        guard let proxy else {
            return try make(host: host, port: port, backend: backend)
        }

        let transport = try make(host: proxy.host, port: UInt16(proxy.port), backend: backend)
        do {
            try await transport.start()
            let client = AsyncProxyClientFactory.make(transport: transport, settings: proxy)
            let leftover = try await client.connect(to: host, port: Int(port))
            if !leftover.isEmpty {
                if let tlsTransport = transport as? AsyncStartTlsTransport {
                    return BufferedAsyncStartTlsTransport(transport: tlsTransport, prebuffer: leftover)
                }
                return BufferedAsyncTransport(transport: transport, prebuffer: leftover)
            }
            return transport
        } catch {
            await transport.stop()
            throw error
        }
    }
}
