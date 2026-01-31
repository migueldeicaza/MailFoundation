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

@Test("IMAP COPYUID response code parsing")
func imapCopyUidResponseParsing() {
    let text = "[COPYUID 7 1:3 5:7] Done"
    let copy = ImapResponseCode.copyUid(from: text)

    #expect(copy?.uidValidity == 7)
    #expect(copy?.source?.description == "1:3")
    #expect(copy?.destination?.description == "5:7")
}

@Test("IMAP store copy returns COPYUID")
func imapStoreCopyReturnsCopyUid() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* 1 EXISTS\r\n".utf8),
        Array("A0002 OK [UIDVALIDITY 7] EXAMINE\r\n".utf8),
        Array("A0003 OK [COPYUID 7 1:2 4:5] COPY\r\n".utf8)
    ])
    let store = ImapMailStore(transport: transport)
    _ = try store.connect()
    _ = try store.authenticate(user: "user", password: "pass")
    _ = try store.openInbox(access: .readOnly)

    let set = SequenceSet([1, 2])
    let result = try store.copy(set, to: "Archive")

    #expect(result.copyUid?.uidValidity == 7)
    #expect(result.copyUid?.source?.description == "1:2")
    #expect(result.copyUid?.destination?.description == "4:5")

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains(where: { $0.contains("COPY 1:2 Archive") }))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP store move returns COPYUID")
func asyncImapStoreMoveReturnsCopyUid() async throws {
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
    await transport.yieldIncoming(Array("A0002 OK [UIDVALIDITY 7] SELECT\r\n".utf8))
    _ = try await openTask.value

    let moveTask = Task { try await store.move("1:2", to: "Archive") }
    await transport.yieldIncoming(Array("A0003 OK [COPYUID 7 1:2 4:5] MOVE\r\n".utf8))
    let result = try await moveTask.value

    #expect(result.copyUid?.uidValidity == 7)
    #expect(result.copyUid?.source?.description == "1:2")
    #expect(result.copyUid?.destination?.description == "4:5")
}
