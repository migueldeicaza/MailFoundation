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

@Test("IMAP quota response parsing")
func imapQuotaResponseParsing() {
    let quota = ImapQuotaResponse.parse("* QUOTA \"INBOX\" (STORAGE 10 512 MESSAGE 2 30)")
    #expect(quota?.root == "INBOX")
    #expect(quota?.resources.count == 2)
    #expect(quota?.resources.first?.name == "STORAGE")
    #expect(quota?.resources.first?.usage == 10)
    #expect(quota?.resources.first?.limit == 512)
}

@Test("IMAP quota root response parsing")
func imapQuotaRootResponseParsing() {
    let root = ImapQuotaRootResponse.parse("* QUOTAROOT \"INBOX\" \"root1\" \"root2\"")
    #expect(root?.mailbox == "INBOX")
    #expect(root?.roots == ["root1", "root2"])
}

@Test("IMAP quota command serialization")
func imapQuotaCommandSerialization() {
    #expect(ImapCommandKind.getQuota("root").command(tag: "A1").serialized == "A1 GETQUOTA root\r\n")
    #expect(ImapCommandKind.getQuotaRoot("INBOX").command(tag: "A2").serialized == "A2 GETQUOTAROOT INBOX\r\n")
}

@Test("IMAP session GETQUOTAROOT parsing")
func imapSessionQuotaRoot() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* QUOTAROOT \"INBOX\" \"root1\"\r\n".utf8),
        Array("* QUOTA \"root1\" (STORAGE 10 512)\r\n".utf8),
        Array("A0002 OK GETQUOTAROOT\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    _ = try session.login(user: "user", password: "pass")

    let result = try session.getQuotaRoot("INBOX")
    #expect(result.quotaRoot?.roots == ["root1"])
    #expect(result.quotas.first?.resources.first?.usage == 10)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session GETQUOTAROOT parsing")
func asyncImapSessionQuotaRoot() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await loginTask.value

    let quotaTask = Task { try await session.getQuotaRoot("INBOX") }
    await transport.yieldIncoming(Array("* QUOTAROOT \"INBOX\" \"root1\"\r\n".utf8))
    await transport.yieldIncoming(Array("* QUOTA \"root1\" (STORAGE 10 512)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK GETQUOTAROOT\r\n".utf8))
    let result = try await quotaTask.value

    #expect(result.quotaRoot?.roots == ["root1"])
    #expect(result.quotas.first?.resources.first?.limit == 512)
}
