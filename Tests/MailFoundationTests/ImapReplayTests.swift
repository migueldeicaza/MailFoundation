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
