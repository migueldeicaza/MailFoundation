import Testing
import Foundation
@testable import MailFoundation

struct Socks5ProxyTests {

    @Test("SOCKS5 proxy client sends greeting and connect request")
    func socks5Connect() async throws {
        let transport = AsyncStreamTransport()
        let client = AsyncSocks5ProxyClient(transport: transport)
        
        // Ensure transport is started
        try await transport.start()

        // Start the client connection process in a background task
        let connectTask = Task {
            try await client.connect(to: "target.example.com", port: 80)
        }

        // --- SOCKS5 Handshake Simulation ---

        // 1. Client sends greeting: [0x05, 0x01, 0x00] (Version 5, 1 auth method, No Auth)
        // Wait for client to send greeting
        var sent = await transport.sentSnapshot()
        var attempts = 0
        while sent.isEmpty {
            if attempts > 100 { throw SessionError.timeout } // 1s timeout
            try await Task.sleep(nanoseconds: 10_000_000)
            sent = await transport.sentSnapshot()
            attempts += 1
        }
        
        let greeting = sent[0]
        #expect(greeting.count >= 3)
        #expect(greeting[0] == 0x05) // Version 5
        
        // 2. Server responds with chosen method: [0x05, 0x00] (Version 5, No Auth)
        await transport.yieldIncoming([0x05, 0x00])

        // 3. Client sends connect request
        // Wait for client to send request
        let previousSentCount = sent.count
        attempts = 0
        while await transport.sentSnapshot().count == previousSentCount {
            if attempts > 100 { throw SessionError.timeout }
            try await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }
        
        sent = await transport.sentSnapshot()
        let request = sent.last!
        #expect(request.count > 6)
        #expect(request[0] == 0x05) // Version 5
        #expect(request[1] == 0x01) // CMD: CONNECT
        #expect(request[3] == 0x03) // ATYP: Domain name (0x03) for "target.example.com"

        // 4. Server responds with success: [0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0] (Success, IPv4 0.0.0.0:0)
        let successResponse: [UInt8] = [
            0x05, 0x00, 0x00, 0x01, 
            0x00, 0x00, 0x00, 0x00, 
            0x00, 0x00
        ]
        await transport.yieldIncoming(successResponse)

        // 5. Connect should complete successfully
        let leftover = try await connectTask.value
        #expect(leftover.isEmpty)
    }
}
