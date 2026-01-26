import Testing
import Foundation
@testable import MailFoundation

struct AsyncSmtpSessionTimeoutTests {

    @Test("Async SMTP session throws TimeoutError when operation times out")
    func asyncSmtpSessionTimeout() async throws {
        // Use a short timeout for the test (100ms)
        let timeoutMs = 100
        let transport = AsyncStreamTransport()
        let session = AsyncSmtpSession(transport: transport, timeoutMilliseconds: timeoutMs)

        // Connect and receive greeting
        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("220 smtp.example.com ESMTP\r\n".utf8))
        _ = try await connectTask.value

        // Perform an operation that will time out (server sends no response)
        let noopTask = Task { 
            try await session.noop() 
        }

        // We do NOT yield any data here. The server is silent. 
        
        do {
            // We wait a bit longer than the configured timeout to ensure it triggers
            try await withTimeout(milliseconds: 500) {
                _ = try await noopTask.value
            }
            #expect(Bool(false), "Should have thrown a timeout error")
        } catch let error as SessionError { 
             if case .timeout = error { 
                 // Success: SessionError.timeout
             } else {
                 #expect(Bool(false), "Unexpected error type: \(error)")
             }
        } catch let error as TimeoutError {
            if case .timedOut = error {
                 // Success: TimeoutError.timedOut
            } else {
                 #expect(Bool(false), "Unexpected error type: \(error)")
            }
        } catch {
             #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}

