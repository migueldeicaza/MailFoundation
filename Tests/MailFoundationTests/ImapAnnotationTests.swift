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

@Test("IMAP annotation response parsing")
func imapAnnotationResponseParsing() {
    let message = ImapLiteralMessage(
        line: "* ANNOTATION \"INBOX\" /comment (/private \"Hello\" /shared NIL)",
        response: ImapResponse.parse("* ANNOTATION \"INBOX\" /comment (/private \"Hello\" /shared NIL)"),
        literal: nil
    )
    let response = ImapAnnotationResponse.parse(message)
    #expect(response?.mailbox == "INBOX")
    #expect(response?.entry.entry == "/comment")
    #expect(response?.entry.attributes.count == 2)
    #expect(response?.entry.attributes.first?.name == "/private")
    #expect(response?.entry.attributes.first?.value == "Hello")
    #expect(response?.entry.attributes.last?.name == "/shared")
    #expect(response?.entry.attributes.last?.value == nil)

    let literalMessage = ImapLiteralMessage(
        line: "* ANNOTATION \"INBOX\" /comment (/private {5})",
        response: ImapResponse.parse("* ANNOTATION \"INBOX\" /comment (/private {5})"),
        literal: Array("Hello".utf8)
    )
    let literalResponse = ImapAnnotationResponse.parse(literalMessage)
    #expect(literalResponse?.entry.attributes.first?.value == "Hello")
}

@Test("IMAP annotation command serialization")
func imapAnnotationCommandSerialization() {
    let getCommand = ImapCommandKind.getAnnotation(
        "INBOX",
        entries: ["/comment"],
        attributes: ["/private", "/shared"]
    )
    .command(tag: "A1")
    .serialized
    #expect(getCommand == "A1 GETANNOTATION INBOX (/comment) (/private /shared)\r\n")

    let setCommand = ImapCommandKind.setAnnotation(
        "INBOX",
        entry: "/comment",
        attributes: [
            ImapAnnotationAttribute(name: "/private", value: "Hello"),
            ImapAnnotationAttribute(name: "/shared", value: nil)
        ]
    )
    .command(tag: "A2")
    .serialized
    #expect(setCommand == "A2 SETANNOTATION INBOX /comment (/private \"Hello\" /shared NIL)\r\n")
}

@Test("IMAP session GETANNOTATION parsing")
func imapSessionGetAnnotation() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* ANNOTATION \"INBOX\" /comment (/private \"Hello\")\r\n".utf8),
        Array("A0002 OK GETANNOTATION\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.login(user: "user", password: "pass")

    let response = try session.getAnnotation(
        mailbox: "INBOX",
        entries: ["/comment"],
        attributes: ["/private"]
    )
    #expect(response?.entries.first?.attributes.first?.value == "Hello")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session SETANNOTATION command")
func asyncImapSessionSetAnnotation() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await loginTask.value

    let setTask = Task {
        try await session.setAnnotation(
            mailbox: "INBOX",
            entry: "/comment",
            attributes: [ImapAnnotationAttribute(name: "/private", value: "Hello")],
            maxEmptyReads: 3
        )
    }
    await transport.yieldIncoming(Array("A0002 OK SETANNOTATION\r\n".utf8))
    _ = try await setTask.value
}
