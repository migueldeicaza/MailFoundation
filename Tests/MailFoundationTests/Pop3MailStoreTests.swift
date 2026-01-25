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

@Test("POP3 store message data")
func pop3StoreMessageData() throws {
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

    let retrData = try store.retrData(1)
    #expect(retrData.data == Array(retrPayload.utf8))

    let topData = try store.topData(1, lines: 1)
    #expect(topData.data == Array(topPayload.utf8))
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

@Test("POP3 folder command helpers")
func pop3FolderCommandHelpers() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK USER\r\n".utf8),
        Array("+OK PASS\r\n".utf8),
        Array("+OK NOOP\r\n".utf8),
        Array("+OK DELE\r\n".utf8),
        Array("+OK RSET\r\n".utf8),
        Array("+OK 7\r\n".utf8)
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let noop = try store.inbox.noop()
    #expect(noop.isSuccess)
    let dele = try store.inbox.dele(2)
    #expect(dele.isSuccess)
    let rset = try store.inbox.rset()
    #expect(rset.isSuccess)
    let last = try store.inbox.last()
    #expect(last == 7)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains("NOOP\r\n"))
    #expect(sent.contains("DELE 2\r\n"))
    #expect(sent.contains("RSET\r\n"))
    #expect(sent.contains("LAST\r\n"))
}

@Test("POP3 store command helpers")
func pop3StoreCommandHelpers() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK USER\r\n".utf8),
        Array("+OK PASS\r\n".utf8),
        Array("+OK NOOP\r\n".utf8),
        Array("+OK DELE\r\n".utf8),
        Array("+OK RSET\r\n".utf8),
        Array("+OK 9\r\n".utf8)
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let noop = try store.noop()
    #expect(noop.isSuccess)
    let dele = try store.dele(3)
    #expect(dele.isSuccess)
    let rset = try store.rset()
    #expect(rset.isSuccess)
    let last = try store.last()
    #expect(last == 9)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains("NOOP\r\n"))
    #expect(sent.contains("DELE 3\r\n"))
    #expect(sent.contains("RSET\r\n"))
    #expect(sent.contains("LAST\r\n"))
}

@Test("POP3 store commands require authentication")
func pop3StoreCommandsRequireAuthentication() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8)
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()

    #expect(throws: SessionError.invalidState(expected: .authenticated, actual: .connected)) {
        _ = try store.noop()
    }
}

@Test("POP3 store command error response")
func pop3StoreCommandErrorResponse() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK USER\r\n".utf8),
        Array("+OK PASS\r\n".utf8),
        Array("-ERR Nope\r\n".utf8)
    ])
    let store = Pop3MailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    do {
        _ = try store.dele(1)
        #expect(Bool(false))
    } catch let error as Pop3CommandError {
        #expect(error.statusText == "Nope")
    } catch {
        #expect(Bool(false))
    }
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
@Test("Async POP3 store message data")
func asyncPop3StoreMessageData() async throws {
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

    let retrTask = Task { try await store.retrData(1) }
    await transport.yieldIncoming(retrChunk)
    let retrData = try await retrTask.value
    #expect(retrData.data == Array(retrPayload.utf8))

    let topTask = Task { try await store.topData(1, lines: 1) }
    await transport.yieldIncoming(topChunk)
    let topData = try await topTask.value
    #expect(topData.data == Array(topPayload.utf8))
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

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 folder command helpers")
func asyncPop3FolderCommandHelpers() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncPop3MailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let noopTask = Task { try await store.inbox.noop() }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    let noop = try await noopTask.value
    #expect(noop?.isSuccess == true)

    let deleTask = Task { try await store.inbox.dele(2) }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    let dele = try await deleTask.value
    #expect(dele?.isSuccess == true)

    let rsetTask = Task { try await store.inbox.rset() }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    let rset = try await rsetTask.value
    #expect(rset?.isSuccess == true)

    let lastTask = Task { try await store.inbox.last() }
    await transport.yieldIncoming(Array("+OK 7\r\n".utf8))
    let last = try await lastTask.value
    #expect(last == 7)

    let sent = await transport.sentSnapshot()
    let sentText = sent.map { String(decoding: $0, as: UTF8.self) }
    #expect(sentText.contains("NOOP\r\n"))
    #expect(sentText.contains("DELE 2\r\n"))
    #expect(sentText.contains("RSET\r\n"))
    #expect(sentText.contains("LAST\r\n"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 store commands require authentication")
func asyncPop3StoreCommandsRequireAuthentication() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncPop3MailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    do {
        _ = try await store.noop()
        #expect(Bool(false))
    } catch {
        #expect(error as? SessionError == .invalidState(expected: .authenticated, actual: .connected))
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 store command error response")
func asyncPop3StoreCommandErrorResponse() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncPop3MailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let deleTask = Task { try await store.dele(1) }
    await transport.yieldIncoming(Array("-ERR Nope\r\n".utf8))
    do {
        _ = try await deleTask.value
        #expect(Bool(false))
    } catch {
        if let popError = error as? Pop3CommandError {
            #expect(popError.statusText == "Nope")
        } else {
            #expect(Bool(false))
        }
    }
}
