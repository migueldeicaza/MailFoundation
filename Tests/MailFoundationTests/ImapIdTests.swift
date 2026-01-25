import Testing
@testable import MailFoundation

@Test("IMAP ID response parsing")
func imapIdResponseParsing() {
    let response = ImapIdResponse.parse("* ID (\"name\" \"server\" \"version\" NIL)")
    #expect(response != nil)
    guard let response else { return }
    #expect(response.values["name"] == "server")
    #expect(response.values["version"] == .some(nil))

    let nilResponse = ImapIdResponse.parse("* ID NIL")
    #expect(nilResponse?.values.isEmpty == true)
}

@Test("IMAP ID command serialization")
func imapIdCommandSerialization() {
    let parameters: [String: String?] = [
        "name": "client",
        "version": nil
    ]
    let command = ImapCommandKind.id(parameters).command(tag: "A1").serialized
    #expect(command == "A1 ID (\"name\" \"client\" \"version\" NIL)\r\n")
}

@Test("IMAP session ID command parsing")
func imapSessionIdCommand() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("* ID (\"name\" \"server\" \"version\" \"1\")\r\n".utf8),
        Array("A0001 OK ID\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()

    let response = try session.id(["name": "client"])
    #expect(response != nil)
    guard let response else { return }
    #expect(response.values["name"] == "server")
    #expect(response.values["version"] == "1")

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains("A0001 ID (\"name\" \"client\")\r\n"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session ID command parsing")
func asyncImapSessionIdCommand() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let idTask = Task { try await session.id(["name": "client"]) }
    await transport.yieldIncoming(Array("* ID (\"name\" \"server\" \"version\" \"1\")\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK ID\r\n".utf8))
    let response = try await idTask.value

    #expect(response != nil)
    guard let response else { return }
    #expect(response.values["name"] == "server")
    #expect(response.values["version"] == "1")
}
