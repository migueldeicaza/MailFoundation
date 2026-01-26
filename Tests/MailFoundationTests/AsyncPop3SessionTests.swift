import Testing
@testable import MailFoundation

// MARK: - Connection & Authentication

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session connects and receives greeting")
func asyncPop3SessionConnect() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    let response = try await connectTask.value

    #expect(response?.isSuccess == true)
    #expect(await session.isConnected == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session USER/PASS authentication")
func asyncPop3SessionUserPassAuth() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK User accepted\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Pass accepted\r\n".utf8))
    let (userResponse, passResponse) = try await authTask.value

    #expect(userResponse?.isSuccess == true)
    #expect(passResponse?.isSuccess == true)
    #expect(await session.isAuthenticated == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session APOP authentication")
func asyncPop3SessionApopAuth() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready <1896.697170952@dbc.mtview.ca.us>\r\n".utf8))
    _ = try await connectTask.value

    let apopTask = Task { try await session.apop(user: "alice", digest: "c4c9334bac560ecc979e58001b3e22fb") }
    await transport.yieldIncoming(Array("+OK maildrop has 1 message (369 octets)\r\n".utf8))
    let response = try await apopTask.value

    #expect(response?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session APOP failure")
func asyncPop3SessionApopFailure() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready <1896.697170952@dbc.mtview.ca.us>\r\n".utf8))
    _ = try await connectTask.value

    let apopTask = Task { try await session.apop(user: "alice", digest: "bad") }
    await transport.yieldIncoming(Array("-ERR Authentication failed\r\n".utf8))

    do {
        _ = try await apopTask.value
        #expect(Bool(false))
    } catch let error as Pop3CommandError {
        #expect(error.statusText == "Authentication failed")
    } catch {
        #expect(Bool(false))
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session AUTH PLAIN")
func asyncPop3SessionAuthPlain() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.auth(mechanism: "PLAIN", initialResponse: "AGFsaWNlAHNlY3JldA==") }
    await transport.yieldIncoming(Array("+OK Authentication successful\r\n".utf8))
    let response = try await authTask.value

    #expect(response?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session AUTH with challenge-response")
func asyncPop3SessionAuthChallengeResponse() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task {
        try await session.auth(mechanism: "CRAM-MD5", initialResponse: nil) { _ in
            return "dXNlciBiOTEzYTYwMmM3ZWRhN2E0OTViNGUyZTA3MzdjNGY2Mw=="
        }
    }
    await transport.yieldIncoming(Array("+ PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Authentication successful\r\n".utf8))
    let response = try await authTask.value

    #expect(response?.isSuccess == true)
}

// MARK: - Capability

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session CAPA command")
func asyncPop3SessionCapability() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let capaTask = Task { try await session.capability() }
    // POP3 CAPA returns multiline response with +OK first, then capabilities, then .
    await transport.yieldIncoming(Array("+OK Capability list follows\r\nTOP\r\nUSER\r\nUIDL\r\nSTLS\r\n.\r\n".utf8))
    let caps = try await capaTask.value

    #expect(caps != nil)
    #expect(caps?.supports("TOP") == true)
    #expect(caps?.supports("USER") == true)
    #expect(caps?.supports("UIDL") == true)
    #expect(caps?.supports("STLS") == true)
}

// MARK: - STAT, LIST, UIDL

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session STAT command")
func asyncPop3SessionStat() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK User accepted\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Pass accepted\r\n".utf8))
    _ = try await authTask.value

    let statTask = Task { try await session.stat() }
    await transport.yieldIncoming(Array("+OK 5 1234\r\n".utf8))
    let stat = try await statTask.value

    #expect(stat.count == 5)
    #expect(stat.size == 1234)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session LIST all messages")
func asyncPop3SessionListAll() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let listTask = Task { try await session.list() }
    await transport.yieldIncoming(Array("+OK 3 messages\r\n".utf8))
    await transport.yieldIncoming(Array("1 120\r\n".utf8))
    await transport.yieldIncoming(Array("2 200\r\n".utf8))
    await transport.yieldIncoming(Array("3 150\r\n".utf8))
    await transport.yieldIncoming(Array(".\r\n".utf8))
    let items = try await listTask.value

    #expect(items.count == 3)
    #expect(items[0].index == 1)
    #expect(items[0].size == 120)
    #expect(items[1].index == 2)
    #expect(items[1].size == 200)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session LIST single message")
func asyncPop3SessionListSingle() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let listTask = Task { try await session.list(2) }
    await transport.yieldIncoming(Array("+OK 2 200\r\n".utf8))
    let item = try await listTask.value

    #expect(item.index == 2)
    #expect(item.size == 200)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session UIDL all messages")
func asyncPop3SessionUidlAll() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let uidlTask = Task { try await session.uidl() }
    await transport.yieldIncoming(Array("+OK unique-id listing follows\r\n".utf8))
    await transport.yieldIncoming(Array("1 whstrstrstr\r\n".utf8))
    await transport.yieldIncoming(Array("2 shsfdgsgh\r\n".utf8))
    await transport.yieldIncoming(Array(".\r\n".utf8))
    let items = try await uidlTask.value

    #expect(items.count == 2)
    #expect(items[0].index == 1)
    #expect(items[0].uid == "whstrstrstr")
    #expect(items[1].index == 2)
    #expect(items[1].uid == "shsfdgsgh")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session UIDL single message")
func asyncPop3SessionUidlSingle() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let uidlTask = Task { try await session.uidl(1) }
    await transport.yieldIncoming(Array("+OK 1 whstrstrstr\r\n".utf8))
    let item = try await uidlTask.value

    #expect(item.index == 1)
    #expect(item.uid == "whstrstrstr")
}

// MARK: - RETR and TOP

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session RETR message")
func asyncPop3SessionRetr() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let retrTask = Task { try await session.retr(1) }
    await transport.yieldIncoming(Array("+OK 120 octets\r\n".utf8))
    await transport.yieldIncoming(Array("From: sender@example.com\r\n".utf8))
    await transport.yieldIncoming(Array("To: alice@example.com\r\n".utf8))
    await transport.yieldIncoming(Array("Subject: Test\r\n".utf8))
    await transport.yieldIncoming(Array("\r\n".utf8))
    await transport.yieldIncoming(Array("Hello, World!\r\n".utf8))
    await transport.yieldIncoming(Array(".\r\n".utf8))
    let lines = try await retrTask.value

    #expect(lines.count == 5)
    #expect(lines[0] == "From: sender@example.com")
    #expect(lines[3] == "")
    #expect(lines[4] == "Hello, World!")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session TOP message")
func asyncPop3SessionTop() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let topTask = Task { try await session.top(1, lines: 2) }
    await transport.yieldIncoming(Array("+OK top of message follows\r\n".utf8))
    await transport.yieldIncoming(Array("From: sender@example.com\r\n".utf8))
    await transport.yieldIncoming(Array("Subject: Test\r\n".utf8))
    await transport.yieldIncoming(Array("\r\n".utf8))
    await transport.yieldIncoming(Array("Line 1\r\n".utf8))
    await transport.yieldIncoming(Array("Line 2\r\n".utf8))
    await transport.yieldIncoming(Array(".\r\n".utf8))
    let lines = try await topTask.value

    #expect(lines.count == 5)
    #expect(lines[0] == "From: sender@example.com")
    #expect(lines[3] == "Line 1")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session RETR as bytes")
func asyncPop3SessionRetrBytes() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let retrTask = Task { try await session.retrBytes(1) }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("Subject: Test\r\n".utf8))
    await transport.yieldIncoming(Array("\r\n".utf8))
    await transport.yieldIncoming(Array("Body\r\n".utf8))
    await transport.yieldIncoming(Array(".\r\n".utf8))
    let bytes = try await retrTask.value

    let text = String(decoding: bytes, as: UTF8.self)
    #expect(text.contains("Subject: Test"))
    #expect(text.contains("Body"))
}

// MARK: - DELE, NOOP, RSET

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session DELE command")
func asyncPop3SessionDele() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let deleTask = Task { try await session.dele(1) }
    await transport.yieldIncoming(Array("+OK message 1 deleted\r\n".utf8))
    let response = try await deleTask.value

    #expect(response?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session NOOP command")
func asyncPop3SessionNoop() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let noopTask = Task { try await session.noop() }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    let response = try await noopTask.value

    #expect(response?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session RSET command")
func asyncPop3SessionRset() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let rsetTask = Task { try await session.rset() }
    await transport.yieldIncoming(Array("+OK maildrop has 2 messages\r\n".utf8))
    let response = try await rsetTask.value

    #expect(response?.isSuccess == true)
}

// MARK: - LAST

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session LAST command")
func asyncPop3SessionLast() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let lastTask = Task { try await session.last() }
    await transport.yieldIncoming(Array("+OK 3\r\n".utf8))
    let lastIndex = try await lastTask.value

    #expect(lastIndex == 3)
}

// MARK: - Error Handling

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session command requires authentication")
func asyncPop3SessionRequiresAuth() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    // Try to STAT without authenticating
    await #expect(throws: SessionError.self) {
        _ = try await session.stat()
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session DELE failure")
func asyncPop3SessionDeleFailure() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let deleTask = Task { try await session.dele(999) }
    await transport.yieldIncoming(Array("-ERR no such message\r\n".utf8))

    await #expect(throws: Pop3CommandError.self) {
        _ = try await deleTask.value
    }
}

// MARK: - Capabilities Accessor

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session capabilities accessor")
func asyncPop3SessionCapabilitiesAccessor() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    // Before CAPA, capabilities should be nil
    let capsBefore = await session.capabilities()
    #expect(capsBefore == nil)

    let capaTask = Task { try await session.capability() }
    await transport.yieldIncoming(Array("+OK Capability list follows\r\nTOP\r\nUIDL\r\n.\r\n".utf8))
    let caps = try await capaTask.value

    // The returned caps should have the capabilities
    #expect(caps?.supports("TOP") == true)
    #expect(caps?.supports("UIDL") == true)

    // And they should also be accessible via the accessor
    let capsAfter = await session.capabilities()
    #expect(capsAfter?.supports("TOP") == true)
    #expect(capsAfter?.supports("UIDL") == true)
}

// MARK: - State Tracking

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session state transitions")
func asyncPop3SessionStateTransitions() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    // Initially disconnected
    #expect(await session.state == .disconnected)
    #expect(await session.isConnected == false)

    // After connect - connected but not authenticated
    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK POP3 server ready\r\n".utf8))
    _ = try await connectTask.value

    #expect(await session.state == .connected)
    #expect(await session.isConnected == true)
    #expect(await session.isAuthenticated == false)

    // After authenticate - authenticated
    let authTask = Task { try await session.authenticate(user: "alice", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    #expect(await session.state == .authenticated)
    #expect(await session.isAuthenticated == true)
}
