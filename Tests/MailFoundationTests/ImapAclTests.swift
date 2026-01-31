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

@Test("IMAP ACL response parsing")
func imapAclResponseParsing() {
    let acl = ImapAclResponse.parse("* ACL \"INBOX\" \"fred\" \"rwipts\" \"david\" \"r\"")
    #expect(acl?.mailbox == "INBOX")
    #expect(acl?.entries.count == 2)
    #expect(acl?.entries.first?.identifier == "fred")
    #expect(acl?.entries.first?.rights == "rwipts")
}

@Test("IMAP ACL list-rights parsing")
func imapListRightsResponseParsing() {
    let response = ImapListRightsResponse.parse("* LISTRIGHTS \"INBOX\" \"fred\" \"rw\" \"ip\" \"t\"")
    #expect(response?.mailbox == "INBOX")
    #expect(response?.identifier == "fred")
    #expect(response?.requiredRights == "rw")
    #expect(response?.optionalRights == ["ip", "t"])
}

@Test("IMAP ACL my-rights parsing")
func imapMyRightsResponseParsing() {
    let response = ImapMyRightsResponse.parse("* MYRIGHTS \"INBOX\" \"rw\"")
    #expect(response?.mailbox == "INBOX")
    #expect(response?.rights == "rw")
}

@Test("IMAP ACL command serialization")
func imapAclCommandSerialization() {
    #expect(ImapCommandKind.getAcl("INBOX").command(tag: "A1").serialized == "A1 GETACL INBOX\r\n")
    #expect(ImapCommandKind.setAcl("INBOX", identifier: "fred", rights: "rw").command(tag: "A2").serialized == "A2 SETACL INBOX fred rw\r\n")
    #expect(ImapCommandKind.listRights("INBOX", identifier: "fred").command(tag: "A3").serialized == "A3 LISTRIGHTS INBOX fred\r\n")
    #expect(ImapCommandKind.myRights("INBOX").command(tag: "A4").serialized == "A4 MYRIGHTS INBOX\r\n")
}

@Test("IMAP session GETACL parsing")
func imapSessionGetAcl() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* ACL \"INBOX\" \"fred\" \"rw\"\r\n".utf8),
        Array("A0002 OK GETACL\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.login(user: "user", password: "pass")

    let response = try session.getAcl(mailbox: "INBOX")
    #expect(response?.entries.first?.identifier == "fred")
    #expect(response?.entries.first?.rights == "rw")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session MYRIGHTS parsing")
func asyncImapSessionMyRights() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await loginTask.value

    let rightsTask = Task { try await session.myRights(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* MYRIGHTS \"INBOX\" \"rw\"\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK MYRIGHTS\r\n".utf8))
    let response = try await rightsTask.value

    #expect(response?.rights == "rw")
}
