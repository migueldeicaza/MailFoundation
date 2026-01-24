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

@Test("Sync SMTP session VRFY/EXPN/HELP parsing")
func syncSmtpSessionAddressParsing() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-User <user@example.com>\r\n250 <other@example.com>\r\n".utf8),
        Array("250-List: <list@example.com>\r\n250 <member@example.com>\r\n".utf8),
        Array("214-Commands:\r\n214 VRFY EXPN HELP\r\n".utf8)
    ])
    let session = SmtpSession(transport: transport, maxReads: 3)
    _ = try session.connect()

    let vrfy = try session.vrfyResult("user")
    let vrfyAddresses = vrfy.mailboxes.map(\.address)
    #expect(vrfyAddresses.contains("user@example.com"))
    #expect(vrfyAddresses.contains("other@example.com"))

    let expn = try session.expnResult("list")
    let expnAddresses = expn.mailboxes.map(\.address)
    #expect(expnAddresses.contains("list@example.com"))
    #expect(expnAddresses.contains("member@example.com"))

    let help = try session.helpResult()
    #expect(help.lines.count == 2)
    #expect(help.text.contains("VRFY"))
}

@Test("Sync SMTP session parses split multiline responses")
func syncSmtpSessionSplitMultilineResponses() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-User <user@example.com>\r".utf8),
        Array("\n250 <other@example.com>\r\n".utf8),
        Array("214-Commands:\r\n214 VRFY".utf8),
        Array(" EXPN HELP\r\n".utf8)
    ])
    let session = SmtpSession(transport: transport, maxReads: 4)
    _ = try session.connect()

    let vrfy = try session.vrfyResult("user")
    let vrfyAddresses = vrfy.mailboxes.map(\.address)
    #expect(vrfyAddresses.contains("user@example.com"))
    #expect(vrfyAddresses.contains("other@example.com"))

    let help = try session.helpResult()
    #expect(help.text.contains("EXPN") == true)
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

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session VRFY/EXPN/HELP parsing")
func asyncSmtpSessionAddressParsing() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let vrfyTask = Task { try await session.vrfyResult("user") }
    await transport.yieldIncoming(Array("250-User <user@example.com>\r\n250 <other@example.com>\r\n".utf8))
    let vrfy = try await vrfyTask.value
    let vrfyAddresses = vrfy.mailboxes.map(\.address)
    #expect(vrfyAddresses.contains("user@example.com"))
    #expect(vrfyAddresses.contains("other@example.com"))

    let expnTask = Task { try await session.expnResult("list") }
    await transport.yieldIncoming(Array("250-List: <list@example.com>\r\n250 <member@example.com>\r\n".utf8))
    let expn = try await expnTask.value
    let expnAddresses = expn.mailboxes.map(\.address)
    #expect(expnAddresses.contains("list@example.com"))
    #expect(expnAddresses.contains("member@example.com"))

    let helpTask = Task { try await session.helpResult() }
    await transport.yieldIncoming(Array("214-Commands:\r\n214 VRFY EXPN HELP\r\n".utf8))
    let help = try await helpTask.value
    #expect(help.lines.count == 2)
    #expect(help.text.contains("VRFY"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session parses split multiline responses")
func asyncSmtpSessionSplitMultilineResponses() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let vrfyTask = Task { try await session.vrfyResult("user") }
    await transport.yieldIncoming(Array("250-User <user@example.com>\r".utf8))
    await transport.yieldIncoming(Array("\n250 <other@example.com>\r\n".utf8))
    let vrfy = try await vrfyTask.value
    let vrfyAddresses = vrfy.mailboxes.map(\.address)
    #expect(vrfyAddresses.contains("user@example.com"))
    #expect(vrfyAddresses.contains("other@example.com"))

    let helpTask = Task { try await session.helpResult() }
    await transport.yieldIncoming(Array("214-Commands:\r\n214 VRFY".utf8))
    await transport.yieldIncoming(Array(" EXPN HELP\r\n".utf8))
    let help = try await helpTask.value
    #expect(help.text.contains("EXPN") == true)
}
