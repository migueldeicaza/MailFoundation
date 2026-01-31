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

@Test("IMAP namespace response parsing")
func imapNamespaceResponseParsing() {
    let response = ImapNamespaceResponse.parse("* NAMESPACE ((\"\" \"/\")) NIL NIL")
    #expect(response != nil)
    guard let response else { return }
    #expect(response.personal.count == 1)
    #expect(response.personal.first?.prefix == "")
    #expect(response.personal.first?.delimiter == "/")
    #expect(response.otherUsers.isEmpty == true)
    #expect(response.shared.isEmpty == true)

    let withExtensions = ImapNamespaceResponse.parse("* NAMESPACE ((\"INBOX.\" \".\" (\"X\" \"Y\"))) ((\"Other/\" \"/\")) ((\"Shared/\" \"/\"))")
    #expect(withExtensions != nil)
    guard let withExtensions else { return }
    #expect(withExtensions.personal.first?.prefix == "INBOX.")
    #expect(withExtensions.personal.first?.delimiter == ".")
    #expect(withExtensions.otherUsers.first?.prefix == "Other/")
    #expect(withExtensions.shared.first?.prefix == "Shared/")
}

@Test("IMAP namespace command serialization")
func imapNamespaceCommandSerialization() {
    let command = ImapCommandKind.namespace.command(tag: "A1").serialized
    #expect(command == "A1 NAMESPACE\r\n")
}

@Test("IMAP session namespace command parsing")
func imapSessionNamespaceCommand() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        ImapTestFixtures.loginOk(),
        Array("* NAMESPACE ((\"\" \"/\")) NIL NIL\r\n".utf8),
        Array("A0002 OK NAMESPACE\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.login(user: "user", password: "pass")

    let response = try session.namespace()
    #expect(response != nil)
    guard let response else { return }
    #expect(response.personal.first?.prefix == "")
    #expect(response.personal.first?.delimiter == "/")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session namespace command parsing")
func asyncImapSessionNamespaceCommand() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(ImapTestFixtures.loginOk())
    _ = try await loginTask.value

    let namespaceTask = Task { try await session.namespace() }
    await transport.yieldIncoming(Array("* NAMESPACE ((\"\" \"/\")) NIL NIL\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK NAMESPACE\r\n".utf8))
    let response = try await namespaceTask.value

    #expect(response != nil)
    guard let response else { return }
    #expect(response.personal.first?.prefix == "")
    #expect(response.personal.first?.delimiter == "/")
}
