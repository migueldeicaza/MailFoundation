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
// RetryPolicyTests.swift
//
// Tests for retry policy functionality.
//

import Foundation
import Testing
@testable import MailFoundation

// MARK: - Test Errors

struct TransientTestError: Error, RetryableError {
    var isRetryable: Bool { true }
}

struct PermanentTestError: Error, RetryableError {
    var isRetryable: Bool { false }
}

struct UnclassifiedTestError: Error {}

// MARK: - Retry Attempt Counter

@available(macOS 10.15, iOS 13.0, *)
actor AttemptCounter {
    var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

// MARK: - RetryPolicy Configuration Tests

@Test("RetryPolicy default values")
func retryPolicyDefaultValues() {
    let policy = RetryPolicy()
    #expect(policy.maxRetries == 3)
    #expect(policy.initialDelayMs == 1000)
    #expect(policy.maxDelayMs == 30000)
    #expect(policy.backoffMultiplier == 2.0)
    #expect(policy.useJitter == true)
}

@Test("RetryPolicy preset configurations")
func retryPolicyPresetConfigurations() {
    #expect(RetryPolicy.none.maxRetries == 0)
    #expect(RetryPolicy.default.maxRetries == 3)
    #expect(RetryPolicy.aggressive.maxRetries == 5)
    #expect(RetryPolicy.aggressive.initialDelayMs == 500)
    #expect(RetryPolicy.conservative.maxRetries == 2)
    #expect(RetryPolicy.conservative.initialDelayMs == 2000)
}

@Test("RetryPolicy linear backoff")
func retryPolicyLinearBackoff() {
    let policy = RetryPolicy.linear(maxRetries: 5, delayMs: 500)
    #expect(policy.maxRetries == 5)
    #expect(policy.initialDelayMs == 500)
    #expect(policy.maxDelayMs == 500)
    #expect(policy.backoffMultiplier == 1.0)
    #expect(policy.useJitter == false)
}

@Test("RetryPolicy delay calculation with exponential backoff")
func retryPolicyDelayCalculation() {
    let policy = RetryPolicy(
        maxRetries: 5,
        initialDelayMs: 100,
        maxDelayMs: 10000,
        backoffMultiplier: 2.0,
        useJitter: false
    )

    #expect(policy.delay(forAttempt: 0) == 100)    // 100 * 2^0 = 100
    #expect(policy.delay(forAttempt: 1) == 200)    // 100 * 2^1 = 200
    #expect(policy.delay(forAttempt: 2) == 400)    // 100 * 2^2 = 400
    #expect(policy.delay(forAttempt: 3) == 800)    // 100 * 2^3 = 800
    #expect(policy.delay(forAttempt: 4) == 1600)   // 100 * 2^4 = 1600
    #expect(policy.delay(forAttempt: 5) == 3200)   // 100 * 2^5 = 3200
    #expect(policy.delay(forAttempt: 10) == 10000) // Capped at maxDelayMs
}

@Test("RetryPolicy delay with jitter varies")
func retryPolicyDelayWithJitter() {
    let policy = RetryPolicy(
        maxRetries: 3,
        initialDelayMs: 1000,
        maxDelayMs: 10000,
        backoffMultiplier: 2.0,
        useJitter: true
    )

    // With jitter, delays should vary but be within bounds
    let delays = (0..<10).map { _ in policy.delay(forAttempt: 0) }
    let uniqueDelays = Set(delays)

    // Should have some variation due to jitter
    // Base is 1000, jitter adds 0-250, so range is 1000-1250
    for delay in delays {
        #expect(delay >= 1000)
        #expect(delay <= 1250)
    }

    // With 10 samples, we should likely have at least 2 different values
    // (though technically all could be the same - just unlikely)
    #expect(uniqueDelays.count > 1)
}

@Test("RetryPolicy equality")
func retryPolicyEquality() {
    let policy1 = RetryPolicy(maxRetries: 3, initialDelayMs: 1000)
    let policy2 = RetryPolicy(maxRetries: 3, initialDelayMs: 1000)
    let policy3 = RetryPolicy(maxRetries: 5, initialDelayMs: 1000)

    #expect(policy1 == policy2)
    #expect(policy1 != policy3)
}

// MARK: - Error Classification Tests

@Test("Error classifier classifies RetryableError correctly")
func errorClassifierRetryableError() {
    let transient = TransientTestError()
    let permanent = PermanentTestError()

    #expect(defaultErrorClassifier(transient) == .transient)
    #expect(defaultErrorClassifier(permanent) == .permanent)
}

@Test("Error classifier classifies TimeoutError as transient")
func errorClassifierTimeoutError() {
    let timeout = TimeoutError.timedOut(milliseconds: 1000)
    let cancelled = TimeoutError.cancelled

    #expect(defaultErrorClassifier(timeout) == .transient)
    #expect(defaultErrorClassifier(cancelled) == .permanent)
}

@Test("Error classifier classifies SessionError correctly")
func errorClassifierSessionError() {
    #expect(defaultErrorClassifier(SessionError.timeout) == .transient)
    #expect(defaultErrorClassifier(SessionError.transportWriteFailed) == .requiresReconnection)
    #expect(defaultErrorClassifier(SessionError.invalidState(expected: .connected, actual: .disconnected)) == .permanent)
    #expect(defaultErrorClassifier(SessionError.startTlsNotSupported) == .permanent)
    #expect(defaultErrorClassifier(SessionError.idleNotSupported) == .permanent)
    #expect(defaultErrorClassifier(SessionError.notifyNotSupported) == .permanent)

    // SMTP 4xx is transient, 5xx is permanent
    #expect(defaultErrorClassifier(SessionError.smtpError(code: 450, message: "Try again", enhancedStatusCode: nil)) == .transient)
    #expect(defaultErrorClassifier(SessionError.smtpError(code: 550, message: "Invalid", enhancedStatusCode: nil)) == .permanent)
}

@Test("Error classifier classifies ConnectionPoolError correctly")
func errorClassifierConnectionPoolError() {
    #expect(defaultErrorClassifier(ConnectionPoolError.poolExhausted) == .transient)
    #expect(defaultErrorClassifier(ConnectionPoolError.connectionFailed(TransientTestError())) == .requiresReconnection)
    #expect(defaultErrorClassifier(ConnectionPoolError.authenticationFailed(PermanentTestError())) == .permanent)
    #expect(defaultErrorClassifier(ConnectionPoolError.poolClosed) == .permanent)
}

@Test("Error classifier defaults to permanent for unknown errors")
func errorClassifierUnknownError() {
    let unknown = UnclassifiedTestError()
    #expect(defaultErrorClassifier(unknown) == .permanent)
}

// MARK: - withRetry Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry succeeds on first attempt")
func withRetrySucceedsFirstAttempt() async throws {
    let counter = AttemptCounter()

    let result = try await withRetry(policy: .default) {
        _ = await counter.increment()
        return "success"
    }

    #expect(result == "success")
    #expect(await counter.value() == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry retries on transient error")
func withRetryRetriesOnTransientError() async throws {
    let counter = AttemptCounter()
    let policy = RetryPolicy.linear(maxRetries: 3, delayMs: 10)

    let result = try await withRetry(policy: policy) {
        let attempt = await counter.increment()
        if attempt < 3 {
            throw TransientTestError()
        }
        return "success after retries"
    }

    #expect(result == "success after retries")
    #expect(await counter.value() == 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry throws immediately on permanent error")
func withRetryThrowsOnPermanentError() async throws {
    let counter = AttemptCounter()

    do {
        _ = try await withRetry(policy: .default) {
            _ = await counter.increment()
            throw PermanentTestError()
        }
        Issue.record("Expected permanent failure")
    } catch let error as RetryError {
        if case .permanentFailure = error {
            // Expected
        } else {
            Issue.record("Expected permanentFailure, got \(error)")
        }
    }

    #expect(await counter.value() == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry exhausts retries on persistent transient error")
func withRetryExhaustsRetries() async throws {
    let counter = AttemptCounter()
    let policy = RetryPolicy.linear(maxRetries: 2, delayMs: 10)

    do {
        _ = try await withRetry(policy: policy) {
            _ = await counter.increment()
            throw TransientTestError()
        }
        Issue.record("Expected exhausted error")
    } catch let error as RetryError {
        if case let .exhausted(_, attempts) = error {
            #expect(attempts == 3) // Initial + 2 retries
        } else {
            Issue.record("Expected exhausted, got \(error)")
        }
    }

    #expect(await counter.value() == 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry with no retries fails immediately")
func withRetryNoRetriesFailsImmediately() async throws {
    let counter = AttemptCounter()

    do {
        _ = try await withRetry(policy: .none) {
            _ = await counter.increment()
            throw TransientTestError()
        }
        Issue.record("Expected exhausted error")
    } catch let error as RetryError {
        if case let .exhausted(_, attempts) = error {
            #expect(attempts == 1)
        } else {
            Issue.record("Expected exhausted, got \(error)")
        }
    }

    #expect(await counter.value() == 1)
}

// MARK: - withRetryResult Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetryResult returns success result")
func withRetryResultReturnsSuccess() async {
    let result = await withRetryResult(policy: .default) {
        return 42
    }

    #expect(result.succeeded)
    #expect(result.value == 42)
    #expect(result.error == nil)
    #expect(result.attempts == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetryResult returns failure result after exhaustion")
func withRetryResultReturnsFailure() async {
    let policy = RetryPolicy.linear(maxRetries: 2, delayMs: 10)

    let result: RetryResult<String> = await withRetryResult(policy: policy) {
        throw TransientTestError()
    }

    #expect(!result.succeeded)
    #expect(result.value == nil)
    #expect(result.error != nil)
    #expect(result.attempts == 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetryResult returns failure on permanent error")
func withRetryResultReturnsFailureOnPermanent() async {
    let result: RetryResult<String> = await withRetryResult(policy: .default) {
        throw PermanentTestError()
    }

    #expect(!result.succeeded)
    #expect(result.attempts == 1)
}

// MARK: - withRetryAndTimeout Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetryAndTimeout succeeds within timeout")
func withRetryAndTimeoutSucceeds() async throws {
    let result = try await withRetryAndTimeout(policy: .default, timeoutMs: 1000) {
        return "fast"
    }

    #expect(result == "fast")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetryAndTimeout retries on timeout")
func withRetryAndTimeoutRetriesOnTimeout() async throws {
    let counter = AttemptCounter()
    let policy = RetryPolicy.linear(maxRetries: 3, delayMs: 10)

    let result = try await withRetryAndTimeout(policy: policy, timeoutMs: 50) {
        let attempt = await counter.increment()
        if attempt < 2 {
            // Simulate slow operation that will timeout
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return "eventually fast"
    }

    #expect(result == "eventually fast")
    #expect(await counter.value() >= 2)
}

// MARK: - Retry Handler Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry calls onRetry handler")
func withRetryCallsOnRetryHandler() async throws {
    let handlerCalls = AttemptCounter()
    let policy = RetryPolicy.linear(maxRetries: 2, delayMs: 10)
    let counter = AttemptCounter()

    let result = try await withRetry(
        policy: policy,
        onRetry: { attempt, error, delayMs in
            _ = await handlerCalls.increment()
            #expect(error is TransientTestError)
            #expect(delayMs == 10)
        }
    ) {
        let attempt = await counter.increment()
        if attempt < 3 {
            throw TransientTestError()
        }
        return "done"
    }

    #expect(result == "done")
    #expect(await handlerCalls.value() == 2) // Called before each retry
}

// MARK: - RetryableError Conformance Tests

@Test("TimeoutError RetryableError conformance")
func timeoutErrorRetryableConformance() {
    #expect(TimeoutError.timedOut(milliseconds: 100).isRetryable == true)
    #expect(TimeoutError.cancelled.isRetryable == false)
}

@Test("SessionError RetryableError conformance")
func sessionErrorRetryableConformance() {
    #expect(SessionError.timeout.isRetryable == true)
    #expect(SessionError.transportWriteFailed.isRetryable == true)
    #expect(SessionError.invalidState(expected: .connected, actual: .disconnected).isRetryable == false)
    #expect(SessionError.startTlsNotSupported.isRetryable == false)
    #expect(SessionError.idleNotSupported.isRetryable == false)
    #expect(SessionError.notifyNotSupported.isRetryable == false)
    #expect(SessionError.smtpError(code: 421, message: "Busy", enhancedStatusCode: nil).isRetryable == true)
    #expect(SessionError.smtpError(code: 550, message: "Invalid", enhancedStatusCode: nil).isRetryable == false)
    #expect(SessionError.pop3Error(message: "Error").isRetryable == false)
    #expect(SessionError.imapError(status: nil, text: "Error").isRetryable == false)
}

@Test("ConnectionPoolError RetryableError conformance")
func connectionPoolErrorRetryableConformance() {
    #expect(ConnectionPoolError.poolExhausted.isRetryable == true)
    #expect(ConnectionPoolError.connectionFailed(TransientTestError()).isRetryable == true)
    #expect(ConnectionPoolError.authenticationFailed(PermanentTestError()).isRetryable == false)
    #expect(ConnectionPoolError.invalidConnection.isRetryable == true)
    #expect(ConnectionPoolError.poolClosed.isRetryable == false)
}

// MARK: - Custom Classifier Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("withRetry with custom classifier")
func withRetryWithCustomClassifier() async throws {
    let counter = AttemptCounter()
    let policy = RetryPolicy.linear(maxRetries: 2, delayMs: 10)

    // Custom classifier that treats UnclassifiedTestError as transient
    let customClassifier: ErrorClassifier = { error in
        if error is UnclassifiedTestError {
            return .transient
        }
        return defaultErrorClassifier(error)
    }

    let result = try await withRetry(policy: policy, classifier: customClassifier) {
        let attempt = await counter.increment()
        if attempt < 2 {
            throw UnclassifiedTestError()
        }
        return "custom classified"
    }

    #expect(result == "custom classified")
    #expect(await counter.value() == 2)
}

// MARK: - SMTP Error Retryable Tests

@Test("SmtpCommandError 4xx codes are retryable")
func smtpCommandError4xxRetryable() {
    // Create SmtpResponse for testing
    let response421 = SmtpResponse(code: 421, lines: ["Service not available"])
    let response450 = SmtpResponse(code: 450, lines: ["Mailbox busy"])
    let response451 = SmtpResponse(code: 451, lines: ["Local error"])

    let error421 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response421)
    let error450 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response450)
    let error451 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response451)

    #expect(error421.isRetryable == true)
    #expect(error450.isRetryable == true)
    #expect(error451.isRetryable == true)
}

@Test("SmtpCommandError 5xx codes are not retryable")
func smtpCommandError5xxNotRetryable() {
    let response550 = SmtpResponse(code: 550, lines: ["Mailbox not found"])
    let response553 = SmtpResponse(code: 553, lines: ["Invalid address"])
    let response554 = SmtpResponse(code: 554, lines: ["Transaction failed"])

    let error550 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response550)
    let error553 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response553)
    let error554 = SmtpCommandError(errorCode: .unexpectedStatusCode, response: response554)

    #expect(error550.isRetryable == false)
    #expect(error553.isRetryable == false)
    #expect(error554.isRetryable == false)
}

@Test("Pop3CommandError is not retryable")
func pop3CommandErrorNotRetryable() {
    let error = Pop3CommandError(statusText: "-ERR", message: "Invalid command")
    #expect(error.isRetryable == false)
}
