import Testing
@testable import MailFoundation

// MARK: - Connection & Authentication

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session connects and receives greeting")
func asyncImapSessionConnect() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK IMAP4rev1 Ready\r\n".utf8))
    let response = try await connectTask.value

    #expect(response?.isOk == true)
    #expect(await session.isConnected == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session handles PREAUTH greeting")
func asyncImapSessionPreauth() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* PREAUTH IMAP4rev1 Logged in\r\n".utf8))
    let response = try await connectTask.value

    #expect(response?.status == .preauth)
    #expect(await session.isAuthenticated == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session login succeeds")
func asyncImapSessionLogin() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    let response = try await loginTask.value

    #expect(response?.isOk == true)
    #expect(await session.isAuthenticated == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session login failure returns NO response")
func asyncImapSessionLoginFailure() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "wrong") }
    await transport.yieldIncoming(Array("A0001 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n".utf8))
    let response = try await loginTask.value

    #expect(response?.status == .no)
    #expect(await session.isAuthenticated == false)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session capability command")
func asyncImapSessionCapability() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    // Greeting includes capabilities
    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK [CAPABILITY IMAP4rev1 IDLE NAMESPACE] Ready\r\n".utf8))
    _ = try await connectTask.value

    let caps = await session.capabilities()
    #expect(caps?.supports("IDLE") == true)
    #expect(caps?.supports("NAMESPACE") == true)
}

// MARK: - Mailbox Operations

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session select mailbox")
func asyncImapSessionSelect() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    // Connect and login
    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    // Select INBOX
    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 RECENT\r\n".utf8))
    await transport.yieldIncoming(Array("* OK [UIDVALIDITY 12345] UIDs valid\r\n".utf8))
    await transport.yieldIncoming(Array("* OK [UIDNEXT 100] Predicted next UID\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8))
    let response = try await selectTask.value

    #expect(response?.isOk == true)
    #expect(await session.selectedMailbox == "INBOX")
    #expect(await session.selectedState.messageCount == 10)
    #expect(await session.selectedState.recentCount == 2)
    #expect(await session.selectedState.uidValidity == 12345)
    #expect(await session.selectedState.uidNext == 100)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session examine mailbox")
func asyncImapSessionExamine() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let examineTask = Task { try await session.examine(mailbox: "Archive") }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK [READ-ONLY] EXAMINE completed\r\n".utf8))
    let response = try await examineTask.value

    #expect(response?.isOk == true)
    #expect(await session.selectedMailbox == "Archive")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session list mailboxes")
func asyncImapSessionList() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let listTask = Task { try await session.list(reference: "", mailbox: "*") }
    await transport.yieldIncoming(Array("* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n".utf8))
    await transport.yieldIncoming(Array("* LIST (\\HasNoChildren) \"/\" \"Sent\"\r\n".utf8))
    await transport.yieldIncoming(Array("* LIST (\\HasNoChildren \\Trash) \"/\" \"Trash\"\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK LIST completed\r\n".utf8))
    let mailboxes = try await listTask.value

    #expect(mailboxes.count == 3)
    #expect(mailboxes[0].name == "INBOX")
    #expect(mailboxes[2].specialUse == .trash)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session create and delete mailbox")
func asyncImapSessionCreateDelete() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    // Create
    let createTask = Task { try await session.create(mailbox: "NewFolder") }
    await transport.yieldIncoming(Array("A0002 OK CREATE completed\r\n".utf8))
    let createResponse = try await createTask.value
    #expect(createResponse.isOk == true)

    // Delete
    let deleteTask = Task { try await session.delete(mailbox: "NewFolder") }
    await transport.yieldIncoming(Array("A0003 OK DELETE completed\r\n".utf8))
    let deleteResponse = try await deleteTask.value
    #expect(deleteResponse.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session rename mailbox")
func asyncImapSessionRename() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let renameTask = Task { try await session.rename(mailbox: "OldName", newName: "NewName") }
    await transport.yieldIncoming(Array("A0002 OK RENAME completed\r\n".utf8))
    let response = try await renameTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session subscribe and unsubscribe")
func asyncImapSessionSubscription() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let subTask = Task { try await session.subscribe(mailbox: "News") }
    await transport.yieldIncoming(Array("A0002 OK SUBSCRIBE completed\r\n".utf8))
    #expect(try await subTask.value.isOk == true)

    let unsubTask = Task { try await session.unsubscribe(mailbox: "News") }
    await transport.yieldIncoming(Array("A0003 OK UNSUBSCRIBE completed\r\n".utf8))
    #expect(try await unsubTask.value.isOk == true)
}

// MARK: - Search & Sort

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session search")
func asyncImapSessionSearch() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let searchTask = Task { try await session.search("UNSEEN") }
    await transport.yieldIncoming(Array("* SEARCH 1 3 5 7\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK SEARCH completed\r\n".utf8))
    let result = try await searchTask.value

    #expect(result.ids == [1, 3, 5, 7])
    #expect(result.isUid == false)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session search with query builder")
func asyncImapSessionSearchQuery() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let query = SearchQuery.from("sender@example.com").and(.unseen)
    let searchTask = Task { try await session.search(query) }
    await transport.yieldIncoming(Array("* SEARCH 2 4\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK SEARCH completed\r\n".utf8))
    let result = try await searchTask.value

    #expect(result.ids == [2, 4])
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session UID search basic")
func asyncImapSessionUidSearchBasic() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let searchTask = Task { try await session.uidSearch("ALL") }
    await transport.yieldIncoming(Array("* SEARCH 101 102 103\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID SEARCH completed\r\n".utf8))
    let result = try await searchTask.value

    #expect(result.ids == [101, 102, 103])
    #expect(result.isUid == true)
}

// MARK: - Fetch

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session fetch")
func asyncImapSessionFetch() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let fetchTask = Task { try await session.fetch("1:3", items: "(FLAGS UID)") }
    await transport.yieldIncoming(Array("* 1 FETCH (FLAGS (\\Seen) UID 101)\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 FETCH (FLAGS () UID 102)\r\n".utf8))
    await transport.yieldIncoming(Array("* 3 FETCH (FLAGS (\\Flagged) UID 103)\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK FETCH completed\r\n".utf8))
    let responses = try await fetchTask.value

    #expect(responses.count == 3)
    #expect(responses[0].sequence == 1)
    #expect(responses[2].sequence == 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session UID fetch")
func asyncImapSessionUidFetch() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    var uidSet = UniqueIdSet()
    uidSet.add(UniqueId(id: 101))
    uidSet.add(UniqueId(id: 102))

    let fetchTask = Task { try await session.uidFetch(uidSet, items: "(FLAGS)") }
    await transport.yieldIncoming(Array("* 1 FETCH (FLAGS (\\Seen) UID 101)\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 FETCH (FLAGS () UID 102)\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID FETCH completed\r\n".utf8))
    let responses = try await fetchTask.value

    #expect(responses.count == 2)
}

// MARK: - Copy & Move

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session copy")
func asyncImapSessionCopy() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let copyTask = Task { try await session.copy("1:2", to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 1:2 201:202] COPY completed\r\n".utf8))
    let result = try await copyTask.value

    #expect(result.response.isOk == true)
    #expect(result.copyUid != nil)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session UID copy")
func asyncImapSessionUidCopy() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    var uidSet = UniqueIdSet()
    uidSet.add(UniqueId(id: 101))

    let copyTask = Task { try await session.uidCopy(uidSet, to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 101 301] UID COPY completed\r\n".utf8))
    let result = try await copyTask.value

    #expect(result.response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session move")
func asyncImapSessionMove() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let moveTask = Task { try await session.move("1", to: "Trash") }
    await transport.yieldIncoming(Array("* 1 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 1 501] MOVE completed\r\n".utf8))
    let result = try await moveTask.value

    #expect(result.response.isOk == true)
}

// MARK: - Status & Namespace

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session status")
func asyncImapSessionStatus() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let statusTask = Task { try await session.status(mailbox: "INBOX", items: ["MESSAGES", "UNSEEN"]) }
    await transport.yieldIncoming(Array("* STATUS INBOX (MESSAGES 10 UNSEEN 3)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK STATUS completed\r\n".utf8))
    let status = try await statusTask.value

    #expect(status.mailbox == "INBOX")
    #expect(status.items["MESSAGES"] == 10)
    #expect(status.items["UNSEEN"] == 3)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session namespace")
func asyncImapSessionNamespace() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let nsTask = Task { try await session.namespace() }
    await transport.yieldIncoming(Array("* NAMESPACE ((\"\" \"/\")) NIL NIL\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK NAMESPACE completed\r\n".utf8))
    let namespace = try await nsTask.value

    #expect(namespace?.personal.first?.prefix == "")
    #expect(namespace?.personal.first?.delimiter == "/")
}

// MARK: - IDLE

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session IDLE")
func asyncImapSessionIdle() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let idleTask = Task { try await session.startIdle() }
    await transport.yieldIncoming(Array("+ idling\r\n".utf8))
    let idleResponse = try await idleTask.value

    #expect(idleResponse.kind == .continuation)
}

// MARK: - Noop & Expunge

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session noop")
func asyncImapSessionNoop() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let noopTask = Task { try await session.noop() }
    await transport.yieldIncoming(Array("A0002 OK NOOP completed\r\n".utf8))
    let response = try await noopTask.value

    #expect(response?.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session expunge")
func asyncImapSessionExpunge() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    let expungeTask = Task { try await session.expunge() }
    await transport.yieldIncoming(Array("* 2 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("* 3 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK EXPUNGE completed\r\n".utf8))
    let response = try await expungeTask.value

    #expect(response.isOk == true)
}

// MARK: - Extensions (Quota, ACL, Metadata, ID)

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session get quota")
func asyncImapSessionGetQuota() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let quotaTask = Task { try await session.getQuota("") }
    await transport.yieldIncoming(Array("* QUOTA \"\" (STORAGE 512 1024)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETQUOTA completed\r\n".utf8))
    let quota = try await quotaTask.value

    #expect(quota?.root == "")
    #expect(quota?.resources.first?.name == "STORAGE")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session get ACL")
func asyncImapSessionGetAcl() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let aclTask = Task { try await session.getAcl(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* ACL INBOX user lrswipkxtecda\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETACL completed\r\n".utf8))
    let acl = try await aclTask.value

    #expect(acl?.mailbox == "INBOX")
    #expect(acl?.entries.first?.identifier == "user")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session ID command")
func asyncImapSessionId() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let idTask = Task { try await session.id(["name": "TestClient", "version": "1.0"]) }
    await transport.yieldIncoming(Array("* ID (\"name\" \"Dovecot\" \"version\" \"2.3\")\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK ID completed\r\n".utf8))
    let response = try await idTask.value

    #expect(response?.values["name"] == "Dovecot")
    #expect(response?.values["version"] == "2.3")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session enable extension")
func asyncImapSessionEnable() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let enableTask = Task { try await session.enable(["QRESYNC", "CONDSTORE"]) }
    await transport.yieldIncoming(Array("* ENABLED QRESYNC CONDSTORE\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK ENABLE completed\r\n".utf8))
    let enabled = try await enableTask.value

    #expect(enabled.contains("QRESYNC"))
    #expect(enabled.contains("CONDSTORE"))
}

// MARK: - Close & Disconnect

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session close mailbox")
func asyncImapSessionClose() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    _ = try await loginTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
    _ = try await selectTask.value

    #expect(await session.selectedMailbox == "INBOX")

    let closeTask = Task { try await session.close() }
    await transport.yieldIncoming(Array("A0003 OK CLOSE completed\r\n".utf8))
    let response = try await closeTask.value

    #expect(response?.isOk == true)
    #expect(await session.selectedMailbox == nil)
}

// MARK: - Split Responses

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session handles complete responses across yields")
func asyncImapSessionSplitResponses() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    // Send complete response in one yield
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    let greeting = try await connectTask.value
    #expect(greeting?.isOk == true)

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    // Send response in multiple yields but each is complete
    await transport.yieldIncoming(Array("A0001 OK LOGIN completed\r\n".utf8))
    let response = try await loginTask.value

    #expect(response?.isOk == true)
}
