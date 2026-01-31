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

@Test("IMAP metadata response parsing")
func imapMetadataResponseParsing() {
    let message = ImapLiteralMessage(
        line: "* METADATA \"INBOX\" (/shared/comment \"Hello\" /shared/empty NIL)",
        response: ImapResponse.parse("* METADATA \"INBOX\" (/shared/comment \"Hello\" /shared/empty NIL)"),
        literal: nil
    )
    let response = ImapMetadataResponse.parse(message)
    #expect(response?.mailbox == "INBOX")
    #expect(response?.entries.count == 2)
    #expect(response?.entries.first?.key == "/shared/comment")
    #expect(response?.entries.first?.value == "Hello")
    #expect(response?.entries.last?.key == "/shared/empty")
    #expect(response?.entries.last?.value == nil)

    let literalMessage = ImapLiteralMessage(
        line: "* METADATA \"INBOX\" (/shared/comment {5})",
        response: ImapResponse.parse("* METADATA \"INBOX\" (/shared/comment {5})"),
        literal: Array("Hello".utf8)
    )
    let literalResponse = ImapMetadataResponse.parse(literalMessage)
    #expect(literalResponse?.entries.first?.value == "Hello")
}

@Test("IMAP metadata command serialization")
func imapMetadataCommandSerialization() {
    let options = ImapMetadataOptions(depth: .zero, maxSize: 512)
    let getCommand = ImapCommandKind.getMetadata("INBOX", options: options, entries: ["/shared/comment"])
        .command(tag: "A1")
        .serialized
    #expect(getCommand == "A1 GETMETADATA INBOX (DEPTH 0 MAXSIZE 512) (/shared/comment)\r\n")

    let setCommand = ImapCommandKind.setMetadata(
        "INBOX",
        entries: [
            ImapMetadataEntry(key: "/shared/comment", value: "Hello"),
            ImapMetadataEntry(key: "/shared/empty", value: nil)
        ]
    )
    .command(tag: "A2")
    .serialized
    #expect(setCommand == "A2 SETMETADATA INBOX (/shared/comment \"Hello\" /shared/empty NIL)\r\n")
}

@Test("IMAP session GETMETADATA parsing")
func imapSessionGetMetadata() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* METADATA \"INBOX\" (/shared/comment \"Hello\")\r\n".utf8),
        Array("A0002 OK GETMETADATA\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.login(user: "user", password: "pass")

    let response = try session.getMetadata(mailbox: "INBOX", entries: ["/shared/comment"])
    #expect(response?.entries.first?.value == "Hello")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session SETMETADATA command")
func asyncImapSessionSetMetadata() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await loginTask.value

    let setTask = Task {
        try await session.setMetadata(
            mailbox: "INBOX",
            entries: [ImapMetadataEntry(key: "/shared/comment", value: "Hello")],
            maxEmptyReads: 3
        )
    }
    await transport.yieldIncoming(Array("A0002 OK SETMETADATA\r\n".utf8))
    _ = try await setTask.value
}
