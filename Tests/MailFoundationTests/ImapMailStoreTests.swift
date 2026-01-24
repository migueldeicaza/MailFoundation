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

@Test("IMAP store folder create/delete via path")
func imapStoreFolderCreateDeleteViaPath() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("A0002 OK CREATE\r\n".utf8),
        Array("A0003 OK DELETE\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let created = try store.createFolder("Archive")
    #expect(created.fullName == "Archive")
    _ = try store.deleteFolder("Archive")
}

@Test("IMAP store folder subscribe/unsubscribe via folder")
func imapStoreFolderSubscribeUnsubscribeViaFolder() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("A0002 OK SUBSCRIBE\r\n".utf8),
        Array("A0003 OK UNSUBSCRIBE\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let folder = try store.getFolder("News")
    _ = try store.subscribeFolder(folder)
    _ = try store.unsubscribeFolder(folder)
}

@Test("IMAP store folder rename updates selection")
func imapStoreFolderRenameUpdatesSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("* 2 EXISTS\r\n".utf8),
        Array("A0002 OK SELECT\r\n".utf8),
        Array("A0003 OK RENAME\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    _ = try store.openInbox(access: .readWrite)
    let renamed = try store.renameFolder("INBOX", to: "Archive")

    #expect(store.selectedFolder === renamed)
    #expect(store.selectedAccess == .readWrite)
}

@Test("IMAP folder rename updates selection")
func imapFolderRenameUpdatesSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("* 2 EXISTS\r\n".utf8),
        Array("A0002 OK SELECT\r\n".utf8),
        Array("A0003 OK RENAME\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let inbox = try store.openInbox(access: .readWrite)
    let renamed = try inbox.rename(to: "Archive")

    #expect(renamed.fullName == "Archive")
    #expect(store.selectedFolder === renamed)
    #expect(store.selectedAccess == .readWrite)
    #expect(renamed.isOpen == true)
}

@Test("IMAP folder delete clears selection")
func imapFolderDeleteClearsSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("A0001 OK LOGIN\r\n".utf8),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK SELECT\r\n".utf8),
        Array("A0003 OK DELETE\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let inbox = try store.openInbox(access: .readWrite)
    _ = try inbox.delete()

    #expect(store.selectedFolder == nil)
    #expect(store.selectedAccess == nil)
    #expect(inbox.isOpen == false)
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

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store folder create/delete via path")
func asyncImapStoreFolderCreateDeleteViaPath() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let createTask = Task { try await store.createFolder("Archive") }
    await transport.yieldIncoming(Array("A0002 OK CREATE\r\n".utf8))
    let created = try await createTask.value
    #expect(created.fullName == "Archive")

    let deleteTask = Task { try await store.deleteFolder("Archive") }
    await transport.yieldIncoming(Array("A0003 OK DELETE\r\n".utf8))
    _ = try await deleteTask.value
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store folder subscribe/unsubscribe via folder")
func asyncImapStoreFolderSubscribeUnsubscribeViaFolder() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let folder = try await store.getFolder("News")
    let subscribeTask = Task { try await store.subscribeFolder(folder) }
    await transport.yieldIncoming(Array("A0002 OK SUBSCRIBE\r\n".utf8))
    _ = try await subscribeTask.value

    let unsubscribeTask = Task { try await store.unsubscribeFolder(folder) }
    await transport.yieldIncoming(Array("A0003 OK UNSUBSCRIBE\r\n".utf8))
    _ = try await unsubscribeTask.value
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store folder rename updates selection")
func asyncImapStoreFolderRenameUpdatesSelection() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 2 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    _ = try await openTask.value

    let renameTask = Task { try await store.renameFolder("INBOX", to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK RENAME\r\n".utf8))
    let renamed = try await renameTask.value

    let selectedFolder = await store.selectedFolder
    #expect(selectedFolder === renamed)
    #expect(await store.selectedAccess == .readWrite)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder rename updates selection")
func asyncImapFolderRenameUpdatesSelection() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let renameTask = Task { try await inbox.rename(to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK RENAME\r\n".utf8))
    let renamed = try await renameTask.value

    let selectedFolder = await store.selectedFolder
    #expect(selectedFolder === renamed)
    #expect(await store.selectedAccess == .readWrite)
    #expect(await renamed.isOpen == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder delete clears selection")
func asyncImapFolderDeleteClearsSelection() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN\r\n".utf8))
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let deleteTask = Task { try await inbox.delete() }
    await transport.yieldIncoming(Array("A0003 OK DELETE\r\n".utf8))
    _ = try await deleteTask.value

    let selectedFolder = await store.selectedFolder
    #expect(selectedFolder == nil)
    #expect(await store.selectedAccess == nil)
    #expect(await inbox.isOpen == false)
}
