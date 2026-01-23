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
