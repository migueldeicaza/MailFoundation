import Testing
@testable import MailFoundation

@Test("Sync SMTP session BDAT chunk")
func syncSmtpSessionBdatChunk() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let session = SmtpSession(transport: transport, maxReads: 2)
    _ = try session.connect()
    let response = try session.sendBdat(Array("Hello".utf8), last: true)
    #expect(response.code == 250)
    #expect(String(decoding: transport.written.first ?? [], as: UTF8.self) == "BDAT 5 LAST\r\n")
    #expect(transport.written.dropFirst().first == Array("Hello".utf8))
}

@Test("Sync SMTP session pipelining")
func syncSmtpSessionPipelined() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("354 End data\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let session = SmtpSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    let response = try session.sendMailPipelined(
        from: "alice@example.com",
        to: ["bob@example.com", "eve@example.com"],
        data: Array("Hello\r\n".utf8)
    )
    #expect(response.code == 250)
    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent[0] == "MAIL FROM:<alice@example.com>\r\n")
    #expect(sent[1] == "RCPT TO:<bob@example.com>\r\n")
    #expect(sent[2] == "RCPT TO:<eve@example.com>\r\n")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session BDAT chunk")
func asyncSmtpSessionBdatChunk() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let bdatTask = Task { try await session.sendBdat(Array("Hello".utf8), last: true) }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await bdatTask.value
    #expect(response.code == 250)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "BDAT 5 LAST\r\n")
    #expect(sent.dropFirst().first == Array("Hello".utf8))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session pipelining")
func asyncSmtpSessionPipelined() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let pipelinedTask = Task {
        try await session.sendMailPipelined(
            from: "alice@example.com",
            to: ["bob@example.com", "eve@example.com"],
            data: Array("Hello\r\n".utf8)
        )
    }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("354 End data\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await pipelinedTask.value
    #expect(response.code == 250)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "MAIL FROM:<alice@example.com>\r\n")
}
