//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Testing
@testable import MailFoundation

@Test("IMAP store open inbox")
func imapStoreOpenInbox() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
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
        ImapTestFixtures.loginOk(),
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
        ImapTestFixtures.loginOk(),
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
        ImapTestFixtures.loginOk(),
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
        ImapTestFixtures.loginOk(),
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
        ImapTestFixtures.loginOk(),
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

@Test("IMAP folder sort")
func imapFolderSort() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8),
        Array("* SORT 2 1\r\n".utf8),
        Array("A0003 OK SORT\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let inbox = try store.openInbox(access: .readOnly)
    let response = try inbox.sort([.arrival], query: .all)
    #expect(response.ids == [2, 1])
}

@Test("IMAP folder search idSet")
func imapFolderSearchIdSet() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8),
        Array("* SEARCH 3 1\r\n".utf8),
        Array("A0003 OK SEARCH\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")

    let inbox = try store.openInbox(access: .readOnly)
    let idSet = try inbox.searchIdSet(.all)

    switch idSet {
    case let .sequence(set):
        #expect(set.count == 2)
        #expect(set.contains(3))
        #expect(set.contains(1))
    case .uid:
        #expect(Bool(false))
    }
}

@Test("IMAP store search idSet uses selected folder")
func imapStoreSearchIdSetUsesSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8),
        Array("* SEARCH 4 2\r\n".utf8),
        Array("A0003 OK SEARCH\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")
    _ = try store.openInbox(access: .readOnly)

    let idSet = try store.searchIdSet(.all)
    switch idSet {
    case let .sequence(set):
        #expect(set.count == 2)
        #expect(set.contains(4))
        #expect(set.contains(2))
    case .uid:
        #expect(Bool(false))
    }
}

@Test("IMAP store search uses selected folder")
func imapStoreSearchUsesSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8),
        Array("* SEARCH 9 6\r\n".utf8),
        Array("A0003 OK SEARCH\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")
    _ = try store.openInbox(access: .readOnly)

    let response = try store.search(.all)
    #expect(response.ids == [9, 6])
}

@Test("IMAP store fetch summaries uses selected folder")
func imapStoreFetchSummariesUsesSelection() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK EXAMINE\r\n".utf8),
        Array("* 1 FETCH (UID 10 FLAGS (\\Seen))\r\n".utf8),
        Array("A0003 OK FETCH\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")
    _ = try store.openInbox(access: .readOnly)

    let request = FetchRequest(items: [.flags, .uniqueId])
    let summaries = try store.fetchSummaries("1", request: request)

    #expect(summaries.count == 1)
    #expect(summaries.first?.uniqueId?.id == 10)
    #expect(summaries.first?.flags.contains(.seen) == true)
}

@Test("IMAP store search idSet requires selection")
func imapStoreSearchIdSetRequiresSelection() throws {
    let store = ImapMailStore(transport: TestTransport(incoming: []))

    #expect(throws: ImapMailStoreError.noSelectedFolder) {
        _ = try store.searchIdSet(.all)
    }
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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
@Test("Async IMAP store search idSet requires selection")
func asyncImapStoreSearchIdSetRequiresSelection() async throws {
    let store = AsyncImapMailStore(transport: AsyncStreamTransport())

    do {
        _ = try await store.searchIdSet(.all)
        #expect(Bool(false))
    } catch let error as ImapMailStoreError {
        #expect(error == .noSelectedFolder)
    } catch {
        #expect(Bool(false))
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store search requires selection")
func asyncImapStoreSearchRequiresSelection() async throws {
    let store = AsyncImapMailStore(transport: AsyncStreamTransport())

    do {
        _ = try await store.search(.all)
        #expect(Bool(false))
    } catch let error as ImapMailStoreError {
        #expect(error == .noSelectedFolder)
    } catch {
        #expect(Bool(false))
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store fetch summaries uses selected folder")
func asyncImapStoreFetchSummariesUsesSelection() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    _ = try await openTask.value

    let request = FetchRequest(items: [.flags, .uniqueId])
    let fetchTask = Task { try await store.fetchSummaries("1", request: request) }
    await transport.yieldIncoming(Array("* 1 FETCH (UID 11 FLAGS (\\Seen))\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK FETCH\r\n".utf8))
    let summaries = try await fetchTask.value

    #expect(summaries.count == 1)
    #expect(summaries.first?.uniqueId?.id == 11)
    #expect(summaries.first?.flags.contains(.seen) == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder sort")
func asyncImapFolderSort() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let sortTask = Task { try await inbox.sort([.arrival], query: .all) }
    await transport.yieldIncoming(Array("* SORT 2 1\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK SORT\r\n".utf8))
    let response = try await sortTask.value

    #expect(response.ids == [2, 1])
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder uidSearch idSet")
func asyncImapFolderUidSearchIdSet() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let searchTask = Task { try await inbox.uidSearchIdSet(.all, validity: 9) }
    await transport.yieldIncoming(Array("* SEARCH 7 8\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID SEARCH\r\n".utf8))
    let idSet = try await searchTask.value

    switch idSet {
    case let .uid(set):
        #expect(set.validity == 9)
        #expect(set.count == 2)
    case .sequence:
        #expect(Bool(false))
    }
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
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

// MARK: - Async IMAP Store Extension Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store ID command")
func asyncImapStoreId() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let idTask = Task { try await store.id(["name": "TestClient", "version": "1.0"]) }
    await transport.yieldIncoming(Array("* ID (\"name\" \"Dovecot\" \"version\" \"2.3\")\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK ID completed\r\n".utf8))
    let response = try await idTask.value

    #expect(response?.values["name"] == "Dovecot")
    #expect(response?.values["version"] == "2.3")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store namespace command")
func asyncImapStoreNamespace() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let nsTask = Task { try await store.namespace() }
    await transport.yieldIncoming(Array("* NAMESPACE ((\"\" \"/\")) ((\"~\" \"/\")) ((\"#shared/\" \"/\"))\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK NAMESPACE completed\r\n".utf8))
    let namespace = try await nsTask.value

    #expect(namespace?.personal.first?.prefix == "")
    #expect(namespace?.personal.first?.delimiter == "/")
    #expect(namespace?.otherUsers.first?.prefix == "~")
    #expect(namespace?.shared.first?.prefix == "#shared/")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store getQuota")
func asyncImapStoreGetQuota() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let quotaTask = Task { try await store.getQuota("") }
    await transport.yieldIncoming(Array("* QUOTA \"\" (STORAGE 512 1024)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETQUOTA completed\r\n".utf8))
    let quota = try await quotaTask.value

    #expect(quota?.root == "")
    #expect(quota?.resources.first?.name == "STORAGE")
    #expect(quota?.resources.first?.usage == 512)
    #expect(quota?.resources.first?.limit == 1024)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store getQuotaRoot")
func asyncImapStoreGetQuotaRoot() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let quotaRootTask = Task { try await store.getQuotaRoot("INBOX") }
    await transport.yieldIncoming(Array("* QUOTAROOT INBOX \"\"\r\n".utf8))
    await transport.yieldIncoming(Array("* QUOTA \"\" (STORAGE 256 512)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETQUOTAROOT completed\r\n".utf8))
    let result = try await quotaRootTask.value

    #expect(result.quotaRoot?.roots.contains("") == true)
    #expect(result.quotas.first?.root == "")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store getAcl")
func asyncImapStoreGetAcl() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let aclTask = Task { try await store.getAcl("INBOX") }
    await transport.yieldIncoming(Array("* ACL INBOX user lrswipkxtecda admin lrswipkxtecda\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETACL completed\r\n".utf8))
    let acl = try await aclTask.value

    #expect(acl?.mailbox == "INBOX")
    #expect(acl?.entries.count == 2)
    #expect(acl?.entries.first?.identifier == "user")
    #expect(acl?.entries.first?.rights == "lrswipkxtecda")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store setAcl")
func asyncImapStoreSetAcl() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let setAclTask = Task { try await store.setAcl("INBOX", identifier: "bob", rights: "lrs") }
    await transport.yieldIncoming(Array("A0002 OK SETACL completed\r\n".utf8))
    let response = try await setAclTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store listRights")
func asyncImapStoreListRights() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let listRightsTask = Task { try await store.listRights("INBOX", identifier: "bob") }
    await transport.yieldIncoming(Array("* LISTRIGHTS INBOX bob lr s w i p k x t e c d a\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK LISTRIGHTS completed\r\n".utf8))
    let response = try await listRightsTask.value

    #expect(response?.mailbox == "INBOX")
    #expect(response?.identifier == "bob")
    #expect(response?.requiredRights == "lr")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store myRights")
func asyncImapStoreMyRights() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let myRightsTask = Task { try await store.myRights("INBOX") }
    await transport.yieldIncoming(Array("* MYRIGHTS INBOX lrswipkxtecda\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK MYRIGHTS completed\r\n".utf8))
    let response = try await myRightsTask.value

    #expect(response?.mailbox == "INBOX")
    #expect(response?.rights == "lrswipkxtecda")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store getMetadata")
func asyncImapStoreGetMetadata() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let metadataTask = Task { try await store.getMetadata("INBOX", entries: ["/private/comment"]) }
    await transport.yieldIncoming(Array("* METADATA INBOX (/private/comment \"My comment\")\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETMETADATA completed\r\n".utf8))
    let response = try await metadataTask.value

    #expect(response?.mailbox == "INBOX")
    #expect(response?.entries.first { $0.key == "/private/comment" }?.value == "My comment")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store setMetadata")
func asyncImapStoreSetMetadata() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let entry = ImapMetadataEntry(key: "/private/comment", value: "New comment")
    let setMetadataTask = Task { try await store.setMetadata("INBOX", entries: [entry]) }
    await transport.yieldIncoming(Array("A0002 OK SETMETADATA completed\r\n".utf8))
    let response = try await setMetadataTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store copy")
func asyncImapStoreCopy() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    _ = try await openTask.value

    let copyTask = Task { try await store.copy("1:2", to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 1:2 101:102] COPY completed\r\n".utf8))
    let result = try await copyTask.value

    #expect(result.response.isOk == true)
    #expect(result.copyUid?.uidValidity == 12345)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store uidCopy")
func asyncImapStoreUidCopy() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    _ = try await openTask.value

    var uidSet = UniqueIdSet()
    uidSet.add(UniqueId(id: 101))
    uidSet.add(UniqueId(id: 102))

    let copyTask = Task { try await store.uidCopy(uidSet, to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 101:102 201:202] UID COPY completed\r\n".utf8))
    let result = try await copyTask.value

    #expect(result.response.isOk == true)
    #expect(result.copyUid != nil)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store uidMove")
func asyncImapStoreUidMove() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    _ = try await openTask.value

    var uidSet = UniqueIdSet()
    uidSet.add(UniqueId(id: 101))

    let moveTask = Task { try await store.uidMove(uidSet, to: "Trash") }
    await transport.yieldIncoming(Array("* 1 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 101 301] UID MOVE completed\r\n".utf8))
    let result = try await moveTask.value

    #expect(result.response.isOk == true)
}

// MARK: - Async IMAP Folder Extension Tests

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder copy")
func asyncImapFolderCopy() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let copyTask = Task { try await inbox.copy("1", to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 1 101] COPY completed\r\n".utf8))
    let result = try await copyTask.value

    #expect(result.response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder move")
func asyncImapFolderMove() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let moveTask = Task { try await inbox.move("1", to: "Trash") }
    await transport.yieldIncoming(Array("* 1 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 12345 1 501] MOVE completed\r\n".utf8))
    let result = try await moveTask.value

    #expect(result.response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder status")
func asyncImapFolderStatus() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let folder = try await store.getFolder("INBOX")
    let statusTask = Task { try await folder.status(items: ["MESSAGES", "UNSEEN", "UIDNEXT"]) }
    await transport.yieldIncoming(Array("* STATUS INBOX (MESSAGES 10 UNSEEN 3 UIDNEXT 100)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK STATUS completed\r\n".utf8))
    let status = try await statusTask.value

    #expect(status.mailbox == "INBOX")
    #expect(status.items["MESSAGES"] == 10)
    #expect(status.items["UNSEEN"] == 3)
    #expect(status.items["UIDNEXT"] == 100)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder expunge")
func asyncImapFolderExpunge() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let expungeTask = Task { try await inbox.expunge() }
    await transport.yieldIncoming(Array("* 2 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("* 3 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK EXPUNGE completed\r\n".utf8))
    let response = try await expungeTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder getQuotaRoot")
func asyncImapFolderGetQuotaRoot() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let quotaRootTask = Task { try await inbox.getQuotaRoot() }
    await transport.yieldIncoming(Array("* QUOTAROOT INBOX \"\"\r\n".utf8))
    await transport.yieldIncoming(Array("* QUOTA \"\" (STORAGE 128 256)\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK GETQUOTAROOT completed\r\n".utf8))
    let result = try await quotaRootTask.value

    #expect(result.quotaRoot?.roots.contains("") == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder getAcl")
func asyncImapFolderGetAcl() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let aclTask = Task { try await inbox.getAcl() }
    await transport.yieldIncoming(Array("* ACL INBOX user lrswipkxtecda\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK GETACL completed\r\n".utf8))
    let acl = try await aclTask.value

    #expect(acl?.mailbox == "INBOX")
    #expect(acl?.entries.first?.identifier == "user")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder setAcl")
func asyncImapFolderSetAcl() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let setAclTask = Task { try await inbox.setAcl(identifier: "bob", rights: "lrs") }
    await transport.yieldIncoming(Array("A0003 OK SETACL completed\r\n".utf8))
    let response = try await setAclTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder myRights")
func asyncImapFolderMyRights() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let myRightsTask = Task { try await inbox.myRights() }
    await transport.yieldIncoming(Array("* MYRIGHTS INBOX lrswipkxtecda\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK MYRIGHTS completed\r\n".utf8))
    let response = try await myRightsTask.value

    #expect(response?.mailbox == "INBOX")
    #expect(response?.rights == "lrswipkxtecda")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder getMetadata")
func asyncImapFolderGetMetadata() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let metadataTask = Task { try await inbox.getMetadata(entries: ["/private/comment"]) }
    await transport.yieldIncoming(Array("* METADATA INBOX (/private/comment \"Folder comment\")\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK GETMETADATA completed\r\n".utf8))
    let response = try await metadataTask.value

    #expect(response?.mailbox == "INBOX")
    #expect(response?.entries.first { $0.key == "/private/comment" }?.value == "Folder comment")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder setMetadata")
func asyncImapFolderSetMetadata() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readWrite) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK SELECT\r\n".utf8))
    let inbox = try await openTask.value

    let entry = ImapMetadataEntry(key: "/private/comment", value: "Updated comment")
    let setMetadataTask = Task { try await inbox.setMetadata(entries: [entry]) }
    await transport.yieldIncoming(Array("A0003 OK SETMETADATA completed\r\n".utf8))
    let response = try await setMetadataTask.value

    #expect(response.isOk == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder uidSort")
func asyncImapFolderUidSort() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let sortTask = Task { try await inbox.uidSort([.reverseDate], query: .all) }
    await transport.yieldIncoming(Array("* SORT 103 102 101\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID SORT completed\r\n".utf8))
    let response = try await sortTask.value

    #expect(response.ids == [103, 102, 101])
    #expect(response.isUid == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder uidSortIdSet")
func asyncImapFolderUidSortIdSet() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let sortTask = Task { try await inbox.uidSortIdSet([.arrival], query: .all, validity: 12345) }
    await transport.yieldIncoming(Array("* SORT 101 102 103\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID SORT completed\r\n".utf8))
    let idSet = try await sortTask.value

    switch idSet {
    case let .uid(set):
        #expect(set.validity == 12345)
        #expect(set.count == 3)
    case .sequence:
        Issue.record("Expected uid set")
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder search with query")
func asyncImapFolderSearchWithQuery() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    let query = SearchQuery.from("sender@example.com").and(.unseen)
    let searchTask = Task { try await inbox.search(query) }
    await transport.yieldIncoming(Array("* SEARCH 2 5 8\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK SEARCH completed\r\n".utf8))
    let response = try await searchTask.value

    #expect(response.ids == [2, 5, 8])
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP folder uidFetchSummaries")
func asyncImapFolderUidFetchSummaries() async throws {
    let transport = AsyncStreamTransport()
    let store = AsyncImapMailStore(transport: transport)

    let connectTask = Task { try await store.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await store.authenticate(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await authTask.value

    let openTask = Task { try await store.openInbox(access: .readOnly) }
    await transport.yieldIncoming(Array("* 10 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
    let inbox = try await openTask.value

    var uidSet = UniqueIdSet()
    uidSet.add(UniqueId(id: 101))
    uidSet.add(UniqueId(id: 102))

    let request = FetchRequest(items: [.flags, .uniqueId])
    let fetchTask = Task { try await inbox.uidFetchSummaries(uidSet, request: request) }
    await transport.yieldIncoming(Array("* 1 FETCH (UID 101 FLAGS (\\Seen))\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 FETCH (UID 102 FLAGS (\\Flagged))\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK UID FETCH completed\r\n".utf8))
    let summaries = try await fetchTask.value

    #expect(summaries.count == 2)
    #expect(summaries[0].uniqueId?.id == 101)
    #expect(summaries[0].flags.contains(.seen) == true)
    #expect(summaries[1].uniqueId?.id == 102)
    #expect(summaries[1].flags.contains(.flagged) == true)
}
