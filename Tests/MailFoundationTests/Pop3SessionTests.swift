import Testing
@testable import MailFoundation

@Test("Sync POP3 session LAST and raw bytes")
func syncPop3SessionLastAndRawBytes() throws {
    let rawLine: [UInt8] = [0x66, 0x6f, 0x6f, 0xff]
    let retrChunk = Array("+OK\r\n".utf8) + rawLine + [0x0d, 0x0a] + [0x2e, 0x0d, 0x0a]
    let topChunk = Array("+OK\r\n".utf8) + rawLine + [0x0d, 0x0a] + [0x2e, 0x0d, 0x0a]

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK\r\n".utf8),
        Array("+OK\r\n".utf8),
        Array("+OK 3\r\n".utf8),
        retrChunk,
        topChunk
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.authenticate(user: "user", password: "pass")
    let last = try session.last()
    #expect(last == 3)
    let retrBytes = try session.retrRaw(1)
    #expect(retrBytes == rawLine)
    let topBytes = try session.topRaw(1, lines: 1)
    #expect(topBytes == rawLine)
}

@Test("Sync POP3 session streaming RETR/TOP")
func syncPop3SessionStreamedData() throws {
    let retrChunk = Array("+OK\r\n".utf8)
        + Array("foo\r\n".utf8)
        + Array("..bar\r\n".utf8)
        + Array(".\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8)
        + Array("baz\r\n".utf8)
        + Array(".\r\n".utf8)

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK\r\n".utf8),
        Array("+OK\r\n".utf8),
        retrChunk,
        topChunk
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.authenticate(user: "user", password: "pass")

    var retrBytes: [UInt8] = []
    try session.retrStream(1) { chunk in
        retrBytes.append(contentsOf: chunk)
    }
    #expect(retrBytes == Array("foo\r\n.bar".utf8))

    var topBytes: [UInt8] = []
    try session.topStream(1, lines: 1) { chunk in
        topBytes.append(contentsOf: chunk)
    }
    #expect(topBytes == Array("baz".utf8))
}

@Test("Sync POP3 session data responses")
func syncPop3SessionDataResponses() throws {
    let retrData = "Subject: Hello\r\n\r\nBody"
    let topData = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrData.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topData.utf8) + Array("\r\n.\r\n".utf8)

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK\r\n".utf8),
        Array("+OK\r\n".utf8),
        retrChunk,
        topChunk
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.authenticate(user: "user", password: "pass")

    let retrResponse = try session.retrData(1)
    #expect(retrResponse.data == Array(retrData.utf8))
    #expect(retrResponse.parseHeaders()[.subject] == "Hello")

    let topResponse = try session.topData(1, lines: 1)
    #expect(topResponse.data == Array(topData.utf8))
    #expect(topResponse.parseHeaders()[.subject] == "Preview")
}

@Test("Sync POP3 session parses split responses")
func syncPop3SessionSplitResponses() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Rea".utf8),
        Array("dy\r\n".utf8),
        Array("+OK U".utf8),
        Array("SER\r\n".utf8),
        Array("+OK P".utf8),
        Array("ASS\r\n".utf8),
        Array("+OK NO".utf8),
        Array("OP\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.authenticate(user: "user", password: "pass")
    let noop = try session.noop()
    #expect(noop.isSuccess)
}

@Test("Sync POP3 session dot-stuffing and empty lines")
func syncPop3SessionDotStuffingAndEmptyLines() throws {
    let dataChunk = Array("+OK\r\n".utf8)
        + Array("\r\n".utf8)
        + Array("..\r\n".utf8)
        + Array("..dot\r\n".utf8)
        + Array("plain\r\n".utf8)
        + Array(".\r\n".utf8)

    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK\r\n".utf8),
        Array("+OK\r\n".utf8),
        dataChunk,
        dataChunk
    ])
    let session = Pop3Session(transport: transport, maxReads: 5)
    _ = try session.connect()
    _ = try session.authenticate(user: "user", password: "pass")

    let expected = Array("\r\n.\r\n.dot\r\nplain".utf8)
    let retrBytes = try session.retrRaw(1)
    #expect(retrBytes == expected)

    var streamed: [UInt8] = []
    try session.retrStream(1) { chunk in
        streamed.append(contentsOf: chunk)
    }
    #expect(streamed == expected)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session LAST and raw bytes")
func asyncPop3SessionLastAndRawBytes() async throws {
    let rawLine: [UInt8] = [0x66, 0x6f, 0x6f, 0xff]
    let retrChunk = Array("+OK\r\n".utf8) + rawLine + [0x0d, 0x0a] + [0x2e, 0x0d, 0x0a]
    let topChunk = Array("+OK\r\n".utf8) + rawLine + [0x0d, 0x0a] + [0x2e, 0x0d, 0x0a]

    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let lastTask = Task { try await session.last() }
    await transport.yieldIncoming(Array("+OK 3\r\n".utf8))
    let last = try await lastTask.value
    #expect(last == 3)

    let retrTask = Task { try await session.retrRaw(1) }
    await transport.yieldIncoming(retrChunk)
    let retrBytes = try await retrTask.value
    #expect(retrBytes == rawLine)

    let topTask = Task { try await session.topRaw(1, lines: 1) }
    await transport.yieldIncoming(topChunk)
    let topBytes = try await topTask.value
    #expect(topBytes == rawLine)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session streaming RETR/TOP")
func asyncPop3SessionStreamedData() async throws {
    let retrChunk = Array("+OK\r\n".utf8)
        + Array("foo\r\n".utf8)
        + Array("..bar\r\n".utf8)
        + Array(".\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8)
        + Array("baz\r\n".utf8)
        + Array(".\r\n".utf8)

    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let retrCollector = ByteCollector()
    let retrTask = Task {
        try await session.retrStream(1) { chunk in
            await retrCollector.append(chunk)
        }
    }
    await transport.yieldIncoming(retrChunk)
    _ = try await retrTask.value
    let retrBytes = await retrCollector.snapshot()
    #expect(retrBytes == Array("foo\r\n.bar".utf8))

    let topCollector = ByteCollector()
    let topTask = Task {
        try await session.topStream(1, lines: 1) { chunk in
            await topCollector.append(chunk)
        }
    }
    await transport.yieldIncoming(topChunk)
    _ = try await topTask.value
    let topBytes = await topCollector.snapshot()
    #expect(topBytes == Array("baz".utf8))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session data responses")
func asyncPop3SessionDataResponses() async throws {
    let retrData = "Subject: Hello\r\n\r\nBody"
    let topData = "Subject: Preview\r\n\r\nLine"
    let retrChunk = Array("+OK\r\n".utf8) + Array(retrData.utf8) + Array("\r\n.\r\n".utf8)
    let topChunk = Array("+OK\r\n".utf8) + Array(topData.utf8) + Array("\r\n.\r\n".utf8)

    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let retrTask = Task { try await session.retrData(1) }
    await transport.yieldIncoming(retrChunk)
    let retrResponse = try await retrTask.value
    #expect(retrResponse.data == Array(retrData.utf8))
    #expect(retrResponse.parseHeaders()[.subject] == "Hello")

    let topTask = Task { try await session.topData(1, lines: 1) }
    await transport.yieldIncoming(topChunk)
    let topResponse = try await topTask.value
    #expect(topResponse.data == Array(topData.utf8))
    #expect(topResponse.parseHeaders()[.subject] == "Preview")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session parses split responses")
func asyncPop3SessionSplitResponses() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Rea".utf8))
    await transport.yieldIncoming(Array("dy\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK U".utf8))
    await transport.yieldIncoming(Array("SER\r\n".utf8))
    await transport.yieldIncoming(Array("+OK P".utf8))
    await transport.yieldIncoming(Array("ASS\r\n".utf8))
    _ = try await authTask.value

    let noopTask = Task { try await session.noop() }
    await transport.yieldIncoming(Array("+OK NO".utf8))
    await transport.yieldIncoming(Array("OP\r\n".utf8))
    let noop = try await noopTask.value
    #expect(noop?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session dot-stuffing and empty lines")
func asyncPop3SessionDotStuffingAndEmptyLines() async throws {
    let dataChunk = Array("+OK\r\n".utf8)
        + Array("\r\n".utf8)
        + Array("..\r\n".utf8)
        + Array("..dot\r\n".utf8)
        + Array("plain\r\n".utf8)
        + Array(".\r\n".utf8)

    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    _ = try await authTask.value

    let expected = Array("\r\n.\r\n.dot\r\nplain".utf8)

    let retrTask = Task { try await session.retrRaw(1) }
    await transport.yieldIncoming(dataChunk)
    let retrBytes = try await retrTask.value
    #expect(retrBytes == expected)

    let collector = ByteCollector()
    let streamTask = Task {
        try await session.retrStream(1) { chunk in
            await collector.append(chunk)
        }
    }
    await transport.yieldIncoming(dataChunk)
    _ = try await streamTask.value
    let streamed = await collector.snapshot()
    #expect(streamed == expected)
}

@available(macOS 10.15, iOS 13.0, *)
private actor ByteCollector {
    private var bytes: [UInt8] = []

    func append(_ chunk: [UInt8]) {
        bytes.append(contentsOf: chunk)
    }

    func snapshot() -> [UInt8] {
        bytes
    }
}
