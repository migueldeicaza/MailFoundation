import Testing
@testable import MailFoundation

@Test("POP3 folder message data")
func pop3FolderMessageData() throws {
    let retrPayload = "Subject: Hello\r\n\r\nBody"
    let topPayload = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrPayload.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topPayload.utf8) + Array("\r\n.\r\n".utf8)

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK USER\r\n".utf8),
        Array("+OK PASS\r\n".utf8),
        retrChunk,
        topChunk
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let retrData = try store.inbox.retrData(1)
    #expect(retrData.data == Array(retrPayload.utf8))
    #expect(retrData.parseHeaders()[.subject] == "Hello")

    let topData = try store.inbox.topData(1, lines: 1)
    #expect(topData.data == Array(topPayload.utf8))
    #expect(topData.parseHeaders()[.subject] == "Preview")
}

@Test("POP3 folder message helpers")
func pop3FolderMessageHelpers() throws {
    let retrPayload = "Subject: Hello\r\n\r\nBody"
    let topPayload = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrPayload.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topPayload.utf8) + Array("\r\n.\r\n".utf8)

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK USER\r\n".utf8),
        Array("+OK PASS\r\n".utf8),
        retrChunk,
        topChunk
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let message = try store.inbox.message(1)
    #expect(message.headers[.subject] == "Hello")

    let headers = try store.inbox.topHeaders(1, lines: 1)
    #expect(headers[.subject] == "Preview")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 folder message data")
func asyncPop3FolderMessageData() async throws {
    let retrPayload = "Subject: Hello\r\n\r\nBody"
    let topPayload = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrPayload.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topPayload.utf8) + Array("\r\n.\r\n".utf8)

    let transport = AsyncStreamTransport()
    let store = AsyncPop3MailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let retrTask = Task { try await store.inbox.retrData(1) }
    await transport.yieldIncoming(retrChunk)
    let retrData = try await retrTask.value
    #expect(retrData.data == Array(retrPayload.utf8))
    #expect(retrData.parseHeaders()[.subject] == "Hello")

    let topTask = Task { try await store.inbox.topData(1, lines: 1) }
    await transport.yieldIncoming(topChunk)
    let topData = try await topTask.value
    #expect(topData.data == Array(topPayload.utf8))
    #expect(topData.parseHeaders()[.subject] == "Preview")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 folder message helpers")
func asyncPop3FolderMessageHelpers() async throws {
    let retrPayload = "Subject: Hello\r\n\r\nBody"
    let topPayload = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrPayload.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topPayload.utf8) + Array("\r\n.\r\n".utf8)

    let transport = AsyncStreamTransport()
    let store = AsyncPop3MailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let messageTask = Task { try await store.inbox.message(1) }
    await transport.yieldIncoming(retrChunk)
    let message = try await messageTask.value
    #expect(message.headers[.subject] == "Hello")

    let topTask = Task { try await store.inbox.topHeaders(1, lines: 1) }
    await transport.yieldIncoming(topChunk)
    let headers = try await topTask.value
    #expect(headers[.subject] == "Preview")
}
