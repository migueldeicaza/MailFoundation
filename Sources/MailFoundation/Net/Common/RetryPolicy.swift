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
// RetryPolicy.swift
//
// Retry policy configuration and utilities for mail operations.
//
// MailKit note: MailKit does not implement a formal retry framework.
// It uses exception hierarchies to distinguish fatal vs non-fatal errors
// and expects applications to implement retry logic. This implementation
// provides a reusable retry framework following common patterns.
//

import Foundation

// MARK: - Retry Policy Configuration

/// Configuration for automatic retry behavior on transient failures.
///
/// `RetryPolicy` defines how operations should be retried when they fail
/// with transient errors such as timeouts, temporary server unavailability,
/// or network issues. It supports exponential backoff with optional jitter
/// to prevent thundering herd problems.
///
/// ## Exponential Backoff
///
/// The delay between retries increases exponentially:
/// ```
/// delay = initialDelayMs * (backoffMultiplier ^ attemptNumber)
/// ```
///
/// For example, with default settings (1s initial, 2x multiplier):
/// - Attempt 1: 1 second delay
/// - Attempt 2: 2 seconds delay
/// - Attempt 3: 4 seconds delay
///
/// ## Jitter
///
/// When ``useJitter`` is enabled, up to 25% random variation is added
/// to prevent multiple clients from retrying simultaneously.
///
/// ## Preset Policies
///
/// Several preset policies are available:
/// - ``default``: 3 retries, 1s initial, exponential backoff
/// - ``aggressive``: 5 retries, 500ms initial, faster recovery
/// - ``conservative``: 2 retries, 2s initial, longer delays
/// - ``none``: No retries, fail immediately
///
/// ## Example Usage
///
/// ```swift
/// // Using default retry policy
/// let result = try await withRetry(policy: .default) {
///     try await mailService.connect()
/// }
///
/// // Custom policy
/// let policy = RetryPolicy(maxRetries: 5, initialDelayMs: 500)
/// let result = try await withRetry(policy: policy) {
///     try await sendMessage()
/// }
/// ```
///
/// - Note: MailKit does not include a formal retry framework. This
///   implementation follows common retry patterns used in distributed systems.
public struct RetryPolicy: Sendable, Equatable {
    /// Maximum number of retry attempts (not including the initial attempt).
    public let maxRetries: Int

    /// Initial delay before the first retry in milliseconds.
    public let initialDelayMs: Int

    /// Maximum delay between retries in milliseconds.
    public let maxDelayMs: Int

    /// Multiplier for exponential backoff (e.g., 2.0 doubles the delay each retry).
    public let backoffMultiplier: Double

    /// Whether to add random jitter to delays to prevent thundering herd.
    public let useJitter: Bool

    /// Creates a retry policy with the specified parameters.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts (default: 3)
    ///   - initialDelayMs: Initial delay in milliseconds (default: 1000)
    ///   - maxDelayMs: Maximum delay in milliseconds (default: 30000)
    ///   - backoffMultiplier: Exponential backoff multiplier (default: 2.0)
    ///   - useJitter: Whether to add random jitter (default: true)
    public init(
        maxRetries: Int = 3,
        initialDelayMs: Int = 1000,
        maxDelayMs: Int = 30000,
        backoffMultiplier: Double = 2.0,
        useJitter: Bool = true
    ) {
        self.maxRetries = max(0, maxRetries)
        self.initialDelayMs = max(0, initialDelayMs)
        self.maxDelayMs = max(initialDelayMs, maxDelayMs)
        self.backoffMultiplier = max(1.0, backoffMultiplier)
        self.useJitter = useJitter
    }

    /// Calculates the delay for a given retry attempt.
    ///
    /// - Parameter attempt: The retry attempt number (0-based)
    /// - Returns: The delay in milliseconds
    public func delay(forAttempt attempt: Int) -> Int {
        let baseDelay = Double(initialDelayMs) * pow(backoffMultiplier, Double(attempt))
        var delay = min(Int(baseDelay), maxDelayMs)

        if useJitter {
            // Add up to 25% jitter
            let jitter = Int.random(in: 0...(delay / 4))
            delay += jitter
        }

        return delay
    }
}

// MARK: - Preset Policies

public extension RetryPolicy {
    /// No retries - fail immediately on first error.
    static let none = RetryPolicy(maxRetries: 0)

    /// Default policy: 3 retries with exponential backoff starting at 1 second.
    static let `default` = RetryPolicy()

    /// Aggressive policy: 5 retries with faster initial delay.
    static let aggressive = RetryPolicy(
        maxRetries: 5,
        initialDelayMs: 500,
        maxDelayMs: 15000,
        backoffMultiplier: 1.5
    )

    /// Conservative policy: 2 retries with longer delays.
    static let conservative = RetryPolicy(
        maxRetries: 2,
        initialDelayMs: 2000,
        maxDelayMs: 60000,
        backoffMultiplier: 3.0
    )

    /// Linear backoff: Fixed delay between retries (no exponential growth).
    static func linear(maxRetries: Int = 3, delayMs: Int = 1000) -> RetryPolicy {
        RetryPolicy(
            maxRetries: maxRetries,
            initialDelayMs: delayMs,
            maxDelayMs: delayMs,
            backoffMultiplier: 1.0,
            useJitter: false
        )
    }
}

// MARK: - Retryable Error Protocol

/// Protocol for errors that can indicate whether they are retryable.
///
/// Errors conforming to this protocol can be automatically classified
/// by the retry system to determine if an operation should be retried.
public protocol RetryableError: Error {
    /// Whether this error is transient and the operation may succeed on retry.
    var isRetryable: Bool { get }
}

// MARK: - Error Classification

/// Classification of an error for retry purposes.
public enum ErrorClassification: Sendable {
    /// The error is transient and the operation should be retried.
    case transient

    /// The error is permanent and retrying will not help.
    case permanent

    /// The error requires reconnection before retrying.
    case requiresReconnection
}

/// A function that classifies errors for retry decisions.
public typealias ErrorClassifier = @Sendable (Error) -> ErrorClassification

/// Default error classifier based on error types.
///
/// This classifier checks specific error types first (for nuanced classification
/// like `.requiresReconnection`), then falls back to `RetryableError` conformance.
public let defaultErrorClassifier: ErrorClassifier = { error in
    // Check specific error types first for nuanced classification

    // Classify TimeoutError
    if let timeoutError = error as? TimeoutError {
        switch timeoutError {
        case .timedOut:
            return .transient
        case .cancelled:
            return .permanent
        }
    }

    // Classify connection pool errors
    if let poolError = error as? ConnectionPoolError {
        switch poolError {
        case .poolExhausted:
            return .transient
        case .connectionFailed:
            return .requiresReconnection
        case .authenticationFailed:
            return .permanent
        case .invalidConnection:
            return .requiresReconnection
        case .poolClosed:
            return .permanent
        }
    }

    // Classify SessionError
    if let sessionError = error as? SessionError {
        switch sessionError {
        case .timeout:
            return .transient
        case .connectionClosed:
            return .requiresReconnection
        case .transportWriteFailed:
            return .requiresReconnection
        case .invalidState:
            return .permanent
        case .invalidImapState:
            return .permanent
        case .startTlsNotSupported:
            return .permanent
        case .compressionNotSupported:
            return .permanent
        case .idleNotSupported:
            return .permanent
        case .notifyNotSupported:
            return .permanent
        case let .smtpError(code, _, _):
            // SMTP 4xx codes are transient, 5xx are permanent
            return (400..<500).contains(code) ? .transient : .permanent
        case .pop3Error:
            return .permanent
        case .imapError:
            return .permanent
        }
    }

    // Classify SmtpCommandError
    if let smtpError = error as? SmtpCommandError {
        // 4xx codes are transient (try again later)
        // 5xx codes are permanent (will never succeed)
        let code = smtpError.statusCode.rawValue
        return (400..<500).contains(code) ? .transient : .permanent
    }

    // Pop3CommandError is generally permanent (command failed)
    if error is Pop3CommandError {
        return .permanent
    }

    // Fall back to RetryableError protocol for unknown error types
    if let retryableError = error as? RetryableError {
        return retryableError.isRetryable ? .transient : .permanent
    }

    // Default: assume permanent to avoid infinite retries
    return .permanent
}

// MARK: - Retry Result

/// The result of a retry operation.
public struct RetryResult<T: Sendable>: Sendable {
    /// The successful result value, if the operation succeeded.
    public let value: T?

    /// The final error, if all attempts failed.
    public let error: Error?

    /// The number of attempts made (including the initial attempt).
    public let attempts: Int

    /// Whether the operation ultimately succeeded.
    public var succeeded: Bool { value != nil }

    /// Creates a successful result.
    public static func success(_ value: T, attempts: Int) -> RetryResult {
        RetryResult(value: value, error: nil, attempts: attempts)
    }

    /// Creates a failed result.
    public static func failure(_ error: Error, attempts: Int) -> RetryResult {
        RetryResult(value: nil, error: error, attempts: attempts)
    }
}

// MARK: - Retry Execution

/// Errors specific to retry operations.
public enum RetryError: Error, Sendable {
    /// All retry attempts exhausted.
    case exhausted(lastError: Error, attempts: Int)

    /// The error was classified as permanent and not retried.
    case permanentFailure(Error)

    /// The operation was cancelled during retry.
    case cancelled
}

/// Executes an async operation with retry logic.
///
/// - Parameters:
///   - policy: The retry policy to use
///   - classifier: Function to classify errors (default: defaultErrorClassifier)
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: `RetryError.exhausted` if all retries fail, or the original error if permanent
@available(macOS 10.15, iOS 13.0, *)
public func withRetry<T: Sendable>(
    policy: RetryPolicy,
    classifier: @escaping ErrorClassifier = defaultErrorClassifier,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var attempt = 0

    while attempt <= policy.maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error

            let classification = classifier(error)

            switch classification {
            case .permanent:
                throw RetryError.permanentFailure(error)

            case .requiresReconnection:
                // For reconnection errors, we still retry but the caller
                // should handle reconnection in the operation closure
                break

            case .transient:
                break
            }

            // Check if we have retries left
            if attempt >= policy.maxRetries {
                break
            }

            // Wait before retrying
            let delayMs = policy.delay(forAttempt: attempt)
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)

            attempt += 1
        }
    }

    throw RetryError.exhausted(lastError: lastError!, attempts: attempt + 1)
}

/// Executes an async operation with retry logic, returning a detailed result.
///
/// Unlike `withRetry`, this function does not throw on failure but returns
/// a `RetryResult` that contains either the success value or the final error.
///
/// - Parameters:
///   - policy: The retry policy to use
///   - classifier: Function to classify errors (default: defaultErrorClassifier)
///   - operation: The async operation to execute
/// - Returns: A `RetryResult` containing the outcome
@available(macOS 10.15, iOS 13.0, *)
public func withRetryResult<T: Sendable>(
    policy: RetryPolicy,
    classifier: @escaping ErrorClassifier = defaultErrorClassifier,
    operation: @Sendable @escaping () async throws -> T
) async -> RetryResult<T> {
    var lastError: Error?
    var attempt = 0

    while attempt <= policy.maxRetries {
        do {
            let result = try await operation()
            return .success(result, attempts: attempt + 1)
        } catch {
            lastError = error

            let classification = classifier(error)

            if classification == .permanent {
                return .failure(error, attempts: attempt + 1)
            }

            if attempt >= policy.maxRetries {
                break
            }

            let delayMs = policy.delay(forAttempt: attempt)
            do {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            } catch {
                return .failure(RetryError.cancelled, attempts: attempt + 1)
            }

            attempt += 1
        }
    }

    return .failure(lastError!, attempts: attempt + 1)
}

/// Executes an async operation with both timeout and retry logic.
///
/// Each attempt is subject to the specified timeout, and failed attempts
/// are retried according to the policy.
///
/// - Parameters:
///   - policy: The retry policy to use
///   - timeoutMs: Timeout for each attempt in milliseconds
///   - classifier: Function to classify errors (default: defaultErrorClassifier)
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: `RetryError.exhausted` if all retries fail
@available(macOS 10.15, iOS 13.0, *)
public func withRetryAndTimeout<T: Sendable>(
    policy: RetryPolicy,
    timeoutMs: Int,
    classifier: @escaping ErrorClassifier = defaultErrorClassifier,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withRetry(policy: policy, classifier: classifier) {
        try await withTimeout(milliseconds: timeoutMs, operation: operation)
    }
}

// MARK: - Retry Handler

/// A handler that is called before each retry attempt.
public typealias RetryHandler = @Sendable (Int, Error, Int) async -> Void

/// Executes an async operation with retry logic and a handler for retry events.
///
/// - Parameters:
///   - policy: The retry policy to use
///   - classifier: Function to classify errors
///   - onRetry: Handler called before each retry with (attempt, error, delayMs)
///   - operation: The async operation to execute
/// - Returns: The result of the operation
@available(macOS 10.15, iOS 13.0, *)
public func withRetry<T: Sendable>(
    policy: RetryPolicy,
    classifier: @escaping ErrorClassifier = defaultErrorClassifier,
    onRetry: @escaping RetryHandler,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var attempt = 0

    while attempt <= policy.maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error

            let classification = classifier(error)

            if classification == .permanent {
                throw RetryError.permanentFailure(error)
            }

            if attempt >= policy.maxRetries {
                break
            }

            let delayMs = policy.delay(forAttempt: attempt)

            // Call the retry handler
            await onRetry(attempt, error, delayMs)

            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)

            attempt += 1
        }
    }

    throw RetryError.exhausted(lastError: lastError!, attempts: attempt + 1)
}

// MARK: - RetryableError Conformances

extension TimeoutError: RetryableError {
    public var isRetryable: Bool {
        switch self {
        case .timedOut:
            return true
        case .cancelled:
            return false
        }
    }
}

extension SessionError: RetryableError {
    public var isRetryable: Bool {
        switch self {
        case .timeout:
            return true
        case .connectionClosed:
            return true // Retryable via reconnection
        case .transportWriteFailed:
            return true // Transient, may succeed after reconnection
        case .invalidState:
            return false
        case .invalidImapState:
            return false
        case .startTlsNotSupported:
            return false
        case .compressionNotSupported:
            return false
        case .idleNotSupported:
            return false
        case .notifyNotSupported:
            return false
        case let .smtpError(code, _, _):
            return (400..<500).contains(code)
        case .pop3Error:
            return false
        case .imapError:
            return false
        }
    }
}

extension SmtpCommandError: RetryableError {
    public var isRetryable: Bool {
        // SMTP 4xx codes are transient (mailbox busy, try again later)
        // SMTP 5xx codes are permanent (invalid address, etc.)
        let code = statusCode.rawValue
        return (400..<500).contains(code)
    }
}

extension Pop3CommandError: RetryableError {
    public var isRetryable: Bool {
        // POP3 command errors are generally permanent
        false
    }
}

extension ConnectionPoolError: RetryableError {
    public var isRetryable: Bool {
        switch self {
        case .poolExhausted:
            return true
        case .connectionFailed:
            return true
        case .authenticationFailed:
            return false
        case .invalidConnection:
            return true
        case .poolClosed:
            return false
        }
    }
}
