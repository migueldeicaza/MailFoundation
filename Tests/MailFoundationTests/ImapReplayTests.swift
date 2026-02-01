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

@Test("IMAP replay Gmail special-use XLIST")
func imapReplayGmailSpecialUseXlist() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "gmail/capability.txt"),
        .command("A0002 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n", fixture: "gmail/authenticate.txt"),
        .command("A0003 NAMESPACE\r\n", fixture: "gmail/gmail.namespace.txt"),
        .command("A0004 XLIST \"\" \"*\"\r\n", fixture: "gmail/xlist.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 5)
    _ = try session.connect()
    _ = try session.authenticateSasl(user: "username", password: "password")

    #expect(session.namespaces != nil)
    #expect(session.specialUseMailboxes.contains { $0.specialUse == .sent })
    #expect(session.specialUseMailboxes.contains { $0.specialUse == .trash })
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay Dovecot special-use LIST")
func imapReplayDovecotSpecialUseList() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "dovecot/authenticate+gmail-capabilities.txt"),
        .command("A0002 NAMESPACE\r\n", fixture: "dovecot/dovecot.namespace.txt"),
        .command("A0003 LIST (SPECIAL-USE) \"\" \"*\"\r\n", fixture: "dovecot/list-special-use.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 5)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")

    #expect(session.specialUseMailboxes.contains { $0.specialUse == .sent })
    #expect(session.specialUseMailboxes.contains { $0.specialUse == .junk })
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay LIST with literal mailbox name")
func imapReplayListWithLiteralMailbox() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "dovecot/authenticate+gmail-capabilities.txt"),
        .command("A0002 NAMESPACE\r\n", fixture: "dovecot/dovecot.namespace.txt"),
        .command("A0003 LIST (SPECIAL-USE) \"\" \"*\"\r\n", fixture: "dovecot/list-special-use.txt"),
        .command("A0004 LIST \"\" \"*\"\r\n", fixture: "common/common.list-literal-subfolders.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")

    let list = try session.list(reference: "", mailbox: "*")
    #expect(list.contains { $0.name == "Literal Folder Name" })
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay STATUS with literal mailbox name")
func imapReplayStatusWithLiteralMailbox() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "dovecot/authenticate+gmail-capabilities.txt"),
        .command("A0002 NAMESPACE\r\n", fixture: "dovecot/dovecot.namespace.txt"),
        .command("A0003 LIST (SPECIAL-USE) \"\" \"*\"\r\n", fixture: "dovecot/list-special-use.txt"),
        .command("A0004 STATUS \"Literal Folder Name\" (MESSAGES)\r\n", fixture: "common/common.status-literal-folder.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")

    let status = try session.status(mailbox: "Literal Folder Name", items: ["MESSAGES"])
    #expect(status.mailbox == "Literal Folder Name")
    #expect(status.items["MESSAGES"] == 60)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay LIST-STATUS return data")
func imapReplayListStatusReturnData() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "gmail/capability.txt"),
        .command("A0002 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n", fixture: "gmail/authenticate.txt"),
        .command("A0003 NAMESPACE\r\n", fixture: "gmail/gmail.namespace.txt"),
        .command("A0004 XLIST \"\" \"*\"\r\n", fixture: "gmail/xlist.txt"),
        .command(
            "A0005 LIST \"\" \"*\" RETURN (STATUS (APPENDLIMIT MESSAGES UNSEEN SIZE))\r\n",
            fixture: "gmail/gmail.list-personal-status-appendlimit.txt"
        )
    ])

    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.authenticateSasl(user: "username", password: "password")

    let responses = try session.listStatus(
        reference: "",
        mailbox: "*",
        items: ["APPENDLIMIT", "MESSAGES", "UNSEEN", "SIZE"]
    )

    let inbox = responses.first { $0.mailbox.name == "INBOX" }
    #expect(inbox?.statusItems["APPENDLIMIT"] == 1234567890)
    #expect(inbox?.statusItems["MESSAGES"] == 10)
    #expect(inbox?.statusItems["UNSEEN"] == 1)
    #expect(inbox?.statusItems["SIZE"] == 123456789)
    #expect(inbox?.mailbox.hasAttribute(.hasNoChildren) == true)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay LIST with NIL delimiter")
func imapReplayListNilDelimiter() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "dovecot/authenticate+gmail-capabilities.txt"),
        .command("A0002 NAMESPACE\r\n", fixture: "dovecot/dovecot.namespace.txt"),
        .command("A0003 LIST (SPECIAL-USE) \"\" \"*\"\r\n", fixture: "dovecot/list-special-use.txt"),
        .command("A0004 LIST \"\" \"*\"\r\n", fixture: "common/common.list-nil-folder-delim.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")

    let list = try session.list(reference: "", mailbox: "*")
    let folder1 = list.first { $0.name == "Folder1" }
    let folder2 = list.first { $0.name == "Folder2" }
    #expect(folder1?.delimiter == nil)
    #expect(folder2?.delimiter == "")
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay LIST-EXTENDED return options")
func imapReplayListExtendedReturnOptions() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting-preauth.txt"),
        .command("A0001 LIST \"\" INBOX RETURN (SUBSCRIBED CHILDREN)\r\n", fixture: "dovecot/dovecot.list-inbox.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()

    let list = try session.listExtended(reference: "", mailbox: "INBOX", returns: [.subscribed, .children])
    let inbox = list.first { $0.name == "INBOX" }
    #expect(inbox?.hasAttribute(.subscribed) == true)
    #expect(inbox?.hasAttribute(.hasNoChildren) == true)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay Gmail FETCH PREVIEW")
func imapReplayFetchPreviewGmail() throws {
    let expected = [
        "Planet Fitness https://view.email.planetfitness.com/?qs=9a098a031cabde68c0a4260051cd6fe473a2e997a53678ff26b4b199a711a9d2ad0536530d6f837c246b09f644d42016ecfb298f930b7af058e9e454b34f3d818ceb3052ae317b1ac4594aab28a2d788 View web ver",
        "Don't miss our celebrity guest Monday evening",
        "Planet Fitness https://view.email.planetfitness.com/?qs=9a098a031cabde68c0a4260051cd6fe473a2e997a53678ff26b4b199a711a9d2ad0536530d6f837c246b09f644d42016ecfb298f930b7af058e9e454b34f3d818ceb3052ae317b1ac4594aab28a2d788 View web ver",
        "Planet Fitness https://view.email.planetfitness.com/?qs=9a098a031cabde68c0a4260051cd6fe473a2e997a53678ff26b4b199a711a9d2ad0536530d6f837c246b09f644d42016ecfb298f930b7af058e9e454b34f3d818ceb3052ae317b1ac4594aab28a2d788 View web ver",
        "Don't miss our celebrity guest Monday evening",
        "Planet Fitness https://view.email.planetfitness.com/?qs=9a098a031cabde68c0a4260051cd6fe473a2e997a53678ff26b4b199a711a9d2ad0536530d6f837c246b09f644d42016ecfb298f930b7af058e9e454b34f3d818ceb3052ae317b1ac4594aab28a2d788 View web ver"
    ]

    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "gmail/capability.txt"),
        .command("A0002 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n", fixture: "gmail/authenticate+preview.txt"),
        .command("A0003 NAMESPACE\r\n", fixture: "gmail/gmail.namespace.txt"),
        .command("A0004 XLIST \"\" \"*\"\r\n", fixture: "gmail/xlist.txt"),
        .command("A0005 EXAMINE INBOX\r\n", fixture: "gmail/examine-inbox.txt"),
        .command("A0006 FETCH 1:* (ENVELOPE FLAGS INTERNALDATE RFC822.SIZE PREVIEW)\r\n", fixture: "gmail/fetch-preview.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 12)
    _ = try session.connect()
    _ = try session.authenticateSasl(user: "username", password: "password")
    _ = try session.examine(mailbox: "INBOX")

    let request = FetchRequest(items: [.envelope, .flags, .internalDate, .size, .previewText])
    let summaries = try session.fetchSummaries("1:*", request: request)
    #expect(summaries.count == expected.count)
    for (summary, value) in zip(summaries, expected) {
        #expect(summary.previewText == value)
    }
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay Gmail FETCH PREVIEW (LAZY)")
func imapReplayFetchPreviewLazyGmail() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "gmail/capability.txt"),
        .command("A0002 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n", fixture: "gmail/authenticate+preview.txt"),
        .command("A0003 NAMESPACE\r\n", fixture: "gmail/gmail.namespace.txt"),
        .command("A0004 XLIST \"\" \"*\"\r\n", fixture: "gmail/xlist.txt"),
        .command("A0005 EXAMINE INBOX\r\n", fixture: "gmail/examine-inbox.txt"),
        .command("A0006 FETCH 1:* (ENVELOPE FLAGS INTERNALDATE RFC822.SIZE PREVIEW (LAZY))\r\n", fixture: "gmail/fetch-preview.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 12)
    _ = try session.connect()
    _ = try session.authenticateSasl(user: "username", password: "password")
    _ = try session.examine(mailbox: "INBOX")

    let request = FetchRequest(
        items: [.envelope, .flags, .internalDate, .size, .previewText],
        previewOptions: .lazy
    )
    let summaries = try session.fetchSummaries("1:*", request: request)
    #expect(summaries.count == 6)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay Gmail PREVIEW fallback via BODY.PEEK")
func imapReplayFetchPreviewFallbackGmail() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "gmail/capability.txt"),
        .command("A0002 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n", fixture: "gmail/authenticate.txt"),
        .command("A0003 NAMESPACE\r\n", fixture: "gmail/gmail.namespace.txt"),
        .command("A0004 XLIST \"\" \"*\"\r\n", fixture: "gmail/xlist.txt"),
        .command("A0005 EXAMINE INBOX\r\n", fixture: "gmail/examine-inbox.txt"),
        .command("A0006 FETCH 1:* BODY.PEEK[TEXT]<0.512>\r\n", fixture: "gmail/fetch-previewtext-peek-text-only.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 12)
    _ = try session.connect()
    _ = try session.authenticateSasl(user: "username", password: "password")
    _ = try session.examine(mailbox: "INBOX")

    let request = FetchRequest(items: [.previewText])
    let summaries = try session.fetchSummaries("1:*", request: request)
    #expect(summaries.count == 2)
    #expect(summaries.allSatisfy { ($0.previewText ?? "").isEmpty == false })
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay IDLE not supported")
func imapReplayIdleNotSupported() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "common/common.login-capability-no-idle.txt"),
        .command("A0002 EXAMINE INBOX\r\n", fixture: "gmail/examine-inbox.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")
    _ = try session.examine(mailbox: "INBOX")

    #expect(throws: SessionError.idleNotSupported) {
        _ = try session.startIdle()
    }
    let wroteIdle = transport.written.contains { String(decoding: $0, as: UTF8.self).contains("IDLE") }
    #expect(wroteIdle == false)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay NOTIFY not supported")
func imapReplayNotifyNotSupported() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 LOGIN username password\r\n", fixture: "common/common.login-capability-no-notify.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.login(user: "username", password: "password")

    #expect(throws: SessionError.notifyNotSupported) {
        _ = try session.notify(arguments: "NONE")
    }
    let wroteNotify = transport.written.contains { String(decoding: $0, as: UTF8.self).contains("NOTIFY") }
    #expect(wroteNotify == false)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay NOTIFY set")
func imapReplayNotifySet() throws {
    let arguments = "SET STATUS (PERSONAL (MailboxName SubscriptionChange)) " +
        "(SELECTED (MessageNew (UID FLAGS ENVELOPE BODYSTRUCTURE MODSEQ) MessageExpunge FlagChange)) " +
        "(SUBTREE (INBOX Folder) (MessageNew MessageExpunge MailboxMetadataChange ServerMetadataChange))"

    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting-preauth.txt"),
        .command("A0001 NOTIFY \(arguments)\r\n", fixture: "dovecot/dovecot.notify.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()

    let response = try session.notify(arguments: arguments)
    #expect(response.isOk)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay NOTIFY flow")
func imapReplayNotifyFlow() throws {
    let arguments = "SET STATUS (PERSONAL (MailboxName SubscriptionChange)) " +
        "(SELECTED (MessageNew (UID FLAGS ENVELOPE BODYSTRUCTURE MODSEQ) MessageExpunge FlagChange)) " +
        "(SUBTREE (INBOX Folder) (MessageNew MessageExpunge MailboxMetadataChange ServerMetadataChange))"

    let transport = ImapReplayTransport(steps: [
        .greeting("dovecot/dovecot.greeting-preauth.txt"),
        .command("A0001 NAMESPACE\r\n", fixture: "dovecot/dovecot.namespace.txt"),
        .command("A0002 LIST \"\" INBOX RETURN (SUBSCRIBED CHILDREN)\r\n", fixture: "dovecot/dovecot.list-inbox.txt"),
        .command("A0003 LIST \"\" \"%\" RETURN (SUBSCRIBED CHILDREN)\r\n", fixture: "dovecot/dovecot.notify-list-personal.txt"),
        .command("A0004 EXAMINE Folder\r\n", fixture: "dovecot/dovecot.examine-folder.txt"),
        .command("A0005 NOTIFY \(arguments)\r\n", fixture: "dovecot/dovecot.notify.txt"),
        .command("A0006 IDLE\r\n", fixture: "dovecot/dovecot.notify-idle.txt"),
        .serverPush("dovecot/dovecot.notify-idle-events.txt"),
        .command("DONE\r\n", fixture: "dovecot/dovecot.notify-idle-done.txt", responseTag: "A0006"),
        .command("A0007 NOTIFY NONE\r\n", fixture: "common/common.notify-none-ok.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 10)
    _ = try session.connect()

    _ = try session.namespace()

    let inbox = try session.listExtended(reference: "", mailbox: "INBOX", returns: [.subscribed, .children])
    #expect(inbox.contains { $0.name == "INBOX" })

    let personal = try session.listExtended(reference: "", mailbox: "%", returns: [.subscribed, .children])
    #expect(personal.contains { $0.name == "Archives" })

    _ = try session.examine(mailbox: "Folder")

    _ = try session.notify(arguments: arguments)
    _ = try session.startIdle()
    let events = session.readIdleEvents()
    #expect(events.isEmpty == false)
    try session.stopIdle()

    _ = try session.notify(arguments: "NONE")
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay COMPRESS")
func imapReplayCompress() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "common/common.capability-compress.txt"),
        .command("A0002 COMPRESS DEFLATE\r\n", fixture: "common/common.compress-ok.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.capability()
    #expect(session.capabilities?.supports("COMPRESS=DEFLATE") == true)

    let response = try session.compress()
    #expect(response.isOk)
    #expect(transport.compressionStarted == true)
    #expect(transport.compressionAlgorithm == "DEFLATE")
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay COMPRESS already active")
func imapReplayCompressAlreadyActive() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "common/common.capability-compress.txt"),
        .command("A0002 COMPRESS DEFLATE\r\n", fixture: "common/common.compress-active.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.capability()
    #expect(session.capabilities?.supports("COMPRESS=DEFLATE") == true)

    let response = try session.compress()
    #expect(response.isOk == false)
    #expect(response.text.contains("COMPRESSIONACTIVE"))
    #expect(transport.compressionStarted == false)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP replay COMPRESS fails")
func imapReplayCompressFails() throws {
    let transport = ImapReplayTransport(steps: [
        .greeting("gmail/gmail.greeting.txt"),
        .command("A0001 CAPABILITY\r\n", fixture: "common/common.capability-compress.txt"),
        .command("A0002 COMPRESS DEFLATE\r\n", fixture: "common/common.compress-failed.txt")
    ])

    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.capability()
    #expect(session.capabilities?.supports("COMPRESS=DEFLATE") == true)

    #expect(throws: SessionError.imapError(status: .no, text: "Compress failed for an unknown reason.")) {
        _ = try session.compress()
    }
    #expect(transport.failures.isEmpty)
}
