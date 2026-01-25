//
// ConnectionPool.swift
//
// Connection pooling for mail services (ported from MailKit patterns).
//

import Foundation

/// Configuration for a mail server connection.
public struct MailServerConfiguration: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public let useTls: Bool
    public let validateCertificate: Bool

    public init(host: String, port: UInt16, useTls: Bool = false, validateCertificate: Bool = true) {
        self.host = host
        self.port = port
        self.useTls = useTls
        self.validateCertificate = validateCertificate
    }
}

/// Credentials for authenticating to a mail server.
public struct MailCredentials: Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Errors that can occur during connection pool operations.
public enum ConnectionPoolError: Error, Sendable {
    case poolExhausted
    case connectionFailed(Error)
    case authenticationFailed(Error)
    case invalidConnection
    case poolClosed
}

/// A handle to a pooled connection. When released, the connection returns to the pool.
@available(macOS 10.15, iOS 13.0, *)
public final class PooledConnection<Service: AsyncMailService>: Sendable where Service: Sendable {
    private let pool: ConnectionPool<Service>
    public let service: Service
    private let releaseAction: @Sendable () async -> Void

    init(pool: ConnectionPool<Service>, service: Service, releaseAction: @escaping @Sendable () async -> Void) {
        self.pool = pool
        self.service = service
        self.releaseAction = releaseAction
    }

    /// Releases the connection back to the pool.
    public func release() async {
        await releaseAction()
    }
}

/// A pool of connections to a mail server.
///
/// Connection pools maintain multiple connections to the same server,
/// allowing concurrent operations without creating new connections for each request.
///
/// Example usage:
/// ```swift
/// let factory: () async throws -> AsyncImapMailStore = {
///     let transport = try AsyncTransportFactory.make(host: "imap.example.com", port: 993, backend: .network)
///     return AsyncImapMailStore(transport: transport)
/// }
/// let pool = ConnectionPool(
///     configuration: MailServerConfiguration(host: "imap.example.com", port: 993, useTls: true),
///     credentials: MailCredentials(username: "user", password: "pass"),
///     maxConnections: 5,
///     serviceFactory: factory
/// )
///
/// let connection = try await pool.acquire()
/// defer { Task { await connection.release() } }
/// // Use connection.service...
/// ```
@available(macOS 10.15, iOS 13.0, *)
public actor ConnectionPool<Service: AsyncMailService> where Service: Sendable {
    public let configuration: MailServerConfiguration
    public let credentials: MailCredentials
    public let maxConnections: Int
    public let retryPolicy: RetryPolicy

    private let serviceFactory: @Sendable () async throws -> Service
    private let authenticator: @Sendable (Service, MailCredentials) async throws -> Void

    private var availableServices: [Service] = []
    private var inUseCount: Int = 0
    private var isClosed: Bool = false
    private var waiters: [CheckedContinuation<Service, Error>] = []

    /// Creates a new connection pool.
    ///
    /// - Parameters:
    ///   - configuration: Server connection configuration
    ///   - credentials: Authentication credentials
    ///   - maxConnections: Maximum number of concurrent connections (default: 5)
    ///   - retryPolicy: Retry policy for connection attempts (default: .default)
    ///   - serviceFactory: Factory function to create new service instances
    ///   - authenticator: Function to authenticate a service with credentials
    public init(
        configuration: MailServerConfiguration,
        credentials: MailCredentials,
        maxConnections: Int = 5,
        retryPolicy: RetryPolicy = .default,
        serviceFactory: @escaping @Sendable () async throws -> Service,
        authenticator: @escaping @Sendable (Service, MailCredentials) async throws -> Void
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.maxConnections = max(1, maxConnections)
        self.retryPolicy = retryPolicy
        self.serviceFactory = serviceFactory
        self.authenticator = authenticator
    }

    /// The number of connections currently available in the pool.
    public var availableCount: Int {
        availableServices.count
    }

    /// The number of connections currently in use.
    public var inUseConnectionCount: Int {
        inUseCount
    }

    /// The total number of active connections (available + in use).
    public var totalConnections: Int {
        availableServices.count + inUseCount
    }

    /// Acquires a connection from the pool.
    ///
    /// If no connections are available and the pool hasn't reached its maximum,
    /// a new connection will be created. If the pool is at capacity, this method
    /// will wait until a connection becomes available.
    ///
    /// - Returns: A pooled connection handle
    /// - Throws: ConnectionPoolError if the pool is closed or connection fails
    public func acquire() async throws -> PooledConnection<Service> {
        guard !isClosed else {
            throw ConnectionPoolError.poolClosed
        }

        let service = try await acquireService()
        return PooledConnection(pool: self, service: service) { [weak self] in
            await self?.release(service)
        }
    }

    private func acquireService() async throws -> Service {
        // Try to get an available connection
        if let service = availableServices.popLast() {
            // Check if it's still connected
            if await service.isConnected {
                inUseCount += 1
                return service
            }
            // Connection is stale, discard it and try to create a new one
        }

        // If we can create a new connection, do so
        // IMPORTANT: Increment inUseCount BEFORE creating to prevent race conditions
        // where multiple tasks pass the capacity check before any completes creation.
        if totalConnections < maxConnections {
            inUseCount += 1
            do {
                let service = try await createAndConnectService()
                return service
            } catch {
                // Creation failed, release the reserved slot
                inUseCount -= 1
                throw error
            }
        }

        // Pool is at capacity, wait for a connection to become available
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func createAndConnectService() async throws -> Service {
        // Capture values for use in @Sendable closure
        let factory = serviceFactory
        let auth = authenticator
        let creds = credentials
        let policy = retryPolicy

        do {
            return try await withRetry(policy: policy) {
                let service = try await factory()
                _ = try await service.connect()

                // Authenticate if not already authenticated
                if await !service.isAuthenticated {
                    try await auth(service, creds)
                }

                return service
            }
        } catch let error as RetryError {
            // Unwrap the retry error to expose the underlying cause
            switch error {
            case .exhausted(let lastError, _):
                throw ConnectionPoolError.connectionFailed(lastError)
            case .permanentFailure(let underlyingError):
                // Check if it was an auth failure
                if underlyingError is ConnectionPoolError {
                    throw underlyingError
                }
                throw ConnectionPoolError.connectionFailed(underlyingError)
            case .cancelled:
                throw ConnectionPoolError.connectionFailed(error)
            }
        } catch {
            throw ConnectionPoolError.connectionFailed(error)
        }
    }

    private func release(_ service: Service) async {
        inUseCount = max(0, inUseCount - 1)

        // If there are waiters, give them the connection directly
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()

            // Check if connection is still valid
            if await service.isConnected {
                inUseCount += 1
                waiter.resume(returning: service)
            } else {
                // Connection is dead, try to create a new one for the waiter
                do {
                    let newService = try await createAndConnectService()
                    inUseCount += 1
                    waiter.resume(returning: newService)
                } catch {
                    waiter.resume(throwing: error)
                }
            }
            return
        }

        // No waiters, return to pool if still connected
        if await service.isConnected && !isClosed {
            availableServices.append(service)
        } else {
            // Disconnect stale connections
            await service.disconnect()
        }
    }

    /// Closes all connections in the pool.
    ///
    /// After calling this method, the pool cannot be used and will throw
    /// `ConnectionPoolError.poolClosed` for any acquire attempts.
    public func close() async {
        isClosed = true

        // Reject all waiters
        for waiter in waiters {
            waiter.resume(throwing: ConnectionPoolError.poolClosed)
        }
        waiters.removeAll()

        // Disconnect all available connections
        for service in availableServices {
            await service.disconnect()
        }
        availableServices.removeAll()
    }

    /// Executes an operation using a pooled connection.
    ///
    /// This is a convenience method that automatically acquires and releases
    /// a connection around the provided operation.
    ///
    /// - Parameter operation: The operation to perform with the connection
    /// - Returns: The result of the operation
    /// - Throws: Any error from acquiring the connection or the operation itself
    public func withConnection<T: Sendable>(_ operation: @Sendable (Service) async throws -> T) async throws -> T {
        let connection = try await acquire()
        do {
            let result = try await operation(connection.service)
            await connection.release()
            return result
        } catch {
            await connection.release()
            throw error
        }
    }

    /// Executes an operation using a pooled connection with automatic retries.
    ///
    /// This method will retry the entire operation (including acquiring a new connection)
    /// on transient failures. Use this for operations that may fail due to temporary
    /// network issues or server unavailability.
    ///
    /// - Parameters:
    ///   - policy: The retry policy to use (defaults to the pool's retry policy)
    ///   - operation: The operation to perform with the connection
    /// - Returns: The result of the operation
    /// - Throws: `RetryError.exhausted` if all retries fail, or the original error if permanent
    public func withRetryingConnection<T: Sendable>(
        policy: RetryPolicy? = nil,
        _ operation: @Sendable @escaping (Service) async throws -> T
    ) async throws -> T {
        let effectivePolicy = policy ?? retryPolicy

        return try await withRetry(policy: effectivePolicy) {
            try await self.withConnection(operation)
        }
    }
}

// MARK: - Convenience Initializers for Specific Service Types

@available(macOS 10.15, iOS 13.0, *)
public extension ConnectionPool where Service == AsyncImapMailStore {
    /// Creates an IMAP connection pool.
    ///
    /// - Parameters:
    ///   - configuration: Server connection configuration
    ///   - credentials: Authentication credentials
    ///   - maxConnections: Maximum number of concurrent connections
    ///   - retryPolicy: Retry policy for connection attempts (default: .default)
    ///   - transportBackend: The transport backend to use (default: .network)
    init(
        configuration: MailServerConfiguration,
        credentials: MailCredentials,
        maxConnections: Int = 5,
        retryPolicy: RetryPolicy = .default,
        transportBackend: AsyncTransportBackend = .network
    ) {
        self.init(
            configuration: configuration,
            credentials: credentials,
            maxConnections: maxConnections,
            retryPolicy: retryPolicy,
            serviceFactory: {
                let transport = try AsyncTransportFactory.make(
                    host: configuration.host,
                    port: configuration.port,
                    backend: transportBackend
                )
                return AsyncImapMailStore(transport: transport)
            },
            authenticator: { service, creds in
                _ = try await service.authenticate(user: creds.username, password: creds.password)
            }
        )
    }
}

@available(macOS 10.15, iOS 13.0, *)
public extension ConnectionPool where Service == AsyncSmtpTransport {
    /// Creates an SMTP connection pool.
    ///
    /// - Parameters:
    ///   - configuration: Server connection configuration
    ///   - credentials: Authentication credentials
    ///   - maxConnections: Maximum number of concurrent connections
    ///   - retryPolicy: Retry policy for connection attempts (default: .default)
    ///   - transportBackend: The transport backend to use (default: .network)
    ///   - localDomain: The local domain for EHLO (default: "localhost")
    init(
        configuration: MailServerConfiguration,
        credentials: MailCredentials,
        maxConnections: Int = 5,
        retryPolicy: RetryPolicy = .default,
        transportBackend: AsyncTransportBackend = .network,
        localDomain: String = "localhost"
    ) {
        self.init(
            configuration: configuration,
            credentials: credentials,
            maxConnections: maxConnections,
            retryPolicy: retryPolicy,
            serviceFactory: {
                try AsyncSmtpTransport.make(
                    host: configuration.host,
                    port: configuration.port,
                    backend: transportBackend
                )
            },
            authenticator: { service, creds in
                _ = try await service.ehlo(domain: localDomain)
                let auth = SmtpSasl.plain(username: creds.username, password: creds.password)
                _ = try await service.authenticate(auth)
            }
        )
    }
}

@available(macOS 10.15, iOS 13.0, *)
public extension ConnectionPool where Service == AsyncPop3MailStore {
    /// Creates a POP3 connection pool.
    ///
    /// - Parameters:
    ///   - configuration: Server connection configuration
    ///   - credentials: Authentication credentials
    ///   - maxConnections: Maximum number of concurrent connections
    ///   - retryPolicy: Retry policy for connection attempts (default: .default)
    ///   - transportBackend: The transport backend to use (default: .network)
    init(
        configuration: MailServerConfiguration,
        credentials: MailCredentials,
        maxConnections: Int = 5,
        retryPolicy: RetryPolicy = .default,
        transportBackend: AsyncTransportBackend = .network
    ) {
        self.init(
            configuration: configuration,
            credentials: credentials,
            maxConnections: maxConnections,
            retryPolicy: retryPolicy,
            serviceFactory: {
                let transport = try AsyncTransportFactory.make(
                    host: configuration.host,
                    port: configuration.port,
                    backend: transportBackend
                )
                return AsyncPop3MailStore(transport: transport)
            },
            authenticator: { service, creds in
                _ = try await service.authenticate(user: creds.username, password: creds.password)
            }
        )
    }
}
