import Testing
@testable import MailFoundation

@Test("IMAP store open inbox")
func imapStoreOpenInbox() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("* 2 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let inbox = try store.openInbox(access: .readOnly)
    #expect(store.selectedFolder === inbox)
    #expect(store.selectedAccess == .readOnly)
    #expect(inbox.isOpen == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store open inbox")
func asyncImapStoreOpenInbox() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 2 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let selectedFolder = await store.selectedFolder
    #expect(selectedFolder === inbox)
    #expect(await store.selectedAccess == .readOnly)
    #expect(await inbox.isOpen == true)
}
