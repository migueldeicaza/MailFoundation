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
