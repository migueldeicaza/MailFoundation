//
// ConnectionPoolTests.swift
//
// Tests for connection pooling infrastructure.
//

import Foundation
import Testing
@testable import MailFoundation

// MARK: - Test Counter Actor

@available(macOS 10.15, iOS 13.0, *)
actor TestCounter {
    var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

// MARK: - Mock Service for Testing

@available(macOS 10.15, iOS 13.0, *)
actor MockMailService: AsyncMailService {
    typealias ConnectResponse = String?

    private var _isConnected = false
    private var _isAuthenticated = false
    var connectCallCount = 0
    var disconnectCallCount = 0
    var authenticateCallCount = 0

    var state: MailServiceState {
        get async {
            if _isAuthenticated { return .authenticated }
            if _isConnected { return .connected }
            return .disconnected
        }
    }

    var isConnected: Bool {
        get async { _isConnected }
    }

    var isAuthenticated: Bool {
        get async { _isAuthenticated }
    }

    @discardableResult
    func connect() async throws -> String? {
        connectCallCount += 1
        _isConnected = true
        return "OK"
    }

    func disconnect() async {
        disconnectCallCount += 1
        _isConnected = false
        _isAuthenticated = false
    }

    func authenticate(user: String, password: String) async throws {
        authenticateCallCount += 1
        _isAuthenticated = true
    }

    func simulateDisconnect() async {
        _isConnected = false
        _isAuthenticated = false
    }
}

// MARK: - Connection Pool Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool creates service on first acquire")
func connectionPoolCreatesOnAcquire() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    let connection = try await pool.acquire()
    #expect(await counter.value() == 1)
    #expect(await connection.service.isConnected)
    #expect(await connection.service.isAuthenticated)
    #expect(await pool.inUseConnectionCount == 1)

    await connection.release()
    #expect(await pool.availableCount == 1)
    #expect(await pool.inUseConnectionCount == 0)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool reuses connections")
func connectionPoolReusesConnections() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // First acquire/release
    let conn1 = try await pool.acquire()
    await conn1.release()

    // Second acquire should reuse the same connection
    let conn2 = try await pool.acquire()
    await conn2.release()

    #expect(await counter.value() == 1)
    #expect(await pool.totalConnections == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool respects max connections")
func connectionPoolRespectsMaxConnections() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 2,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Acquire two connections (max)
    let conn1 = try await pool.acquire()
    let conn2 = try await pool.acquire()

    #expect(await counter.value() == 2)
    #expect(await pool.inUseConnectionCount == 2)
    #expect(await pool.availableCount == 0)

    // Release both
    await conn1.release()
    await conn2.release()

    #expect(await pool.availableCount == 2)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool waits when at capacity")
func connectionPoolWaitsAtCapacity() async throws {
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 1,
        serviceFactory: { MockMailService() },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Acquire the only connection
    let conn1 = try await pool.acquire()

    // Start a task that will wait for a connection
    let acquireTask = Task {
        try await pool.acquire()
    }

    // Give the task time to start waiting
    try await Task.sleep(nanoseconds: 50_000_000)

    // Release the first connection - the waiting task should get it
    await conn1.release()

    let conn2 = try await acquireTask.value
    #expect(await conn2.service.isConnected)

    await conn2.release()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool discards stale connections")
func connectionPoolDiscardsStaleConnections() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Acquire and release a connection
    let conn1 = try await pool.acquire()
    let service = conn1.service
    await conn1.release()

    // Simulate the connection becoming stale
    await service.simulateDisconnect()

    // Next acquire should create a new connection since the old one is stale
    let conn2 = try await pool.acquire()
    #expect(await counter.value() == 2)
    #expect(await conn2.service.isConnected)

    await conn2.release()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool close disconnects all")
func connectionPoolCloseDisconnectsAll() async throws {
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: { MockMailService() },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Acquire and release connections to populate the pool
    let conn1 = try await pool.acquire()
    let conn2 = try await pool.acquire()
    await conn1.release()
    await conn2.release()

    #expect(await pool.availableCount == 2)

    // Close the pool
    await pool.close()

    #expect(await pool.availableCount == 0)

    // Trying to acquire after close should fail
    do {
        _ = try await pool.acquire()
        Issue.record("Expected pool closed error")
    } catch ConnectionPoolError.poolClosed {
        // Expected
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool withConnection helper")
func connectionPoolWithConnectionHelper() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Use withConnection helper
    let result = try await pool.withConnection { service in
        #expect(await service.isAuthenticated)
        return "success"
    }

    #expect(result == "success")
    #expect(await counter.value() == 1)
    #expect(await pool.availableCount == 1)
    #expect(await pool.inUseConnectionCount == 0)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool withConnection releases on error")
func connectionPoolWithConnectionReleasesOnError() async throws {
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: { MockMailService() },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    struct TestError: Error {}

    do {
        _ = try await pool.withConnection { _ in
            throw TestError()
        }
        Issue.record("Expected error to be thrown")
    } catch is TestError {
        // Expected
    }

    // Connection should be released back to pool
    #expect(await pool.availableCount == 1)
    #expect(await pool.inUseConnectionCount == 0)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("MailServerConfiguration equality")
func mailServerConfigurationEquality() async throws {
    let config1 = MailServerConfiguration(host: "imap.example.com", port: 993, useTls: true)
    let config2 = MailServerConfiguration(host: "imap.example.com", port: 993, useTls: true)
    let config3 = MailServerConfiguration(host: "smtp.example.com", port: 587, useTls: false)

    #expect(config1 == config2)
    #expect(config1 != config3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool multiple concurrent operations")
func connectionPoolMultipleConcurrentOperations() async throws {
    let counter = TestCounter()
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            await counter.increment()
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    // Run multiple concurrent operations
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<5 {
            group.addTask {
                do {
                    try await pool.withConnection { service in
                        // Simulate some work
                        try await Task.sleep(nanoseconds: 10_000_000)
                        _ = await service.isConnected
                    }
                } catch {
                    Issue.record("Unexpected error: \(error)")
                }
            }
        }
    }

    // Should have created at most maxConnections
    #expect(await counter.value() <= 3)
    #expect(await pool.totalConnections <= 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool handles connection factory errors")
func connectionPoolHandlesFactoryErrors() async throws {
    struct FactoryError: Error {}

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        serviceFactory: {
            throw FactoryError()
        },
        authenticator: { _, _ in }
    )

    do {
        _ = try await pool.acquire()
        Issue.record("Expected connection error")
    } catch ConnectionPoolError.connectionFailed {
        // Expected
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool handles authentication errors")
func connectionPoolHandlesAuthenticationErrors() async throws {
    struct AuthError: Error {}

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: .none, // Disable retries for this test
        serviceFactory: { MockMailService() },
        authenticator: { _, _ in
            throw AuthError()
        }
    )

    do {
        _ = try await pool.acquire()
        Issue.record("Expected connection error")
    } catch ConnectionPoolError.connectionFailed {
        // Expected (auth errors are wrapped in connectionFailed)
    }
}

// MARK: - Retry Integration Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool retries transient connection failures")
func connectionPoolRetriesTransientFailures() async throws {
    let counter = TestCounter()

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: RetryPolicy.linear(maxRetries: 3, delayMs: 10),
        serviceFactory: {
            await counter.increment()
            let count = await counter.value()
            // Fail first 2 attempts with a transient error
            if count < 3 {
                throw TimeoutError.timedOut(milliseconds: 1000)
            }
            return MockMailService()
        },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    let connection = try await pool.acquire()
    #expect(await counter.value() == 3) // Should have taken 3 attempts
    #expect(await connection.service.isConnected)

    await connection.release()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool exhausts retries on persistent failure")
func connectionPoolExhaustsRetries() async throws {
    let counter = TestCounter()

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: RetryPolicy.linear(maxRetries: 2, delayMs: 10),
        serviceFactory: {
            await counter.increment()
            throw TimeoutError.timedOut(milliseconds: 1000)
        },
        authenticator: { _, _ in }
    )

    do {
        _ = try await pool.acquire()
        Issue.record("Expected connection error after retries exhausted")
    } catch ConnectionPoolError.connectionFailed {
        // Expected - should have tried 3 times (initial + 2 retries)
        #expect(await counter.value() == 3)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool does not retry permanent failures")
func connectionPoolDoesNotRetryPermanentFailures() async throws {
    let counter = TestCounter()

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: RetryPolicy.linear(maxRetries: 3, delayMs: 10),
        serviceFactory: {
            await counter.increment()
            // PermanentTestError would be classified as permanent
            throw PermanentTestError()
        },
        authenticator: { _, _ in }
    )

    do {
        _ = try await pool.acquire()
        Issue.record("Expected connection error")
    } catch ConnectionPoolError.connectionFailed {
        // Should only try once since it's a permanent error
        #expect(await counter.value() == 1)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool withRetryingConnection retries operation")
func connectionPoolWithRetryingConnectionRetriesOperation() async throws {
    let operationCounter = TestCounter()

    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: RetryPolicy.linear(maxRetries: 3, delayMs: 10),
        serviceFactory: { MockMailService() },
        authenticator: { service, creds in
            try await service.authenticate(user: creds.username, password: creds.password)
        }
    )

    let result = try await pool.withRetryingConnection { service in
        await operationCounter.increment()
        let count = await operationCounter.value()
        if count < 2 {
            throw TransientTestError()
        }
        return "success after retry"
    }

    #expect(result == "success after retry")
    #expect(await operationCounter.value() == 2)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Connection pool stores retry policy")
func connectionPoolStoresRetryPolicy() async throws {
    let policy = RetryPolicy.aggressive
    let pool = ConnectionPool<MockMailService>(
        configuration: MailServerConfiguration(host: "test.example.com", port: 993),
        credentials: MailCredentials(username: "user", password: "pass"),
        maxConnections: 3,
        retryPolicy: policy,
        serviceFactory: { MockMailService() },
        authenticator: { _, _ in }
    )

    #expect(await pool.retryPolicy == policy)
}
