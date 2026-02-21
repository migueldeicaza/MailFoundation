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

import Foundation
import Testing
@testable import MailFoundation

extension ProtocolLogger: @unchecked Sendable {}

private func memoryStreamOutput(_ stream: OutputStream) -> String {
    let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()
    return String(decoding: data, as: UTF8.self)
}

private func extractTag(from command: String) -> String? {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let firstSpace = trimmed.firstIndex(of: " ") else {
        return nil
    }
    return String(trimmed[..<firstSpace])
}

@available(macOS 10.15, iOS 13.0, *)
private func awaitSentCommand(transport: AsyncStreamTransport, contains token: String, attempts: Int = 50) async -> String? {
    for _ in 0..<attempts {
        let sent = await transport.sentSnapshot()
        if let line = sent.compactMap({ String(decoding: $0, as: UTF8.self) }).first(where: { $0.contains(token) }) {
            return line
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return nil
}

private final class SyncLiteralContinuationTransport: Transport {
    var incoming: [[UInt8]]
    var written: [[UInt8]] = []

    init(incoming: [[UInt8]] = []) {
        self.incoming = incoming
    }

    func open() {}
    func close() {}

    func write(_ bytes: [UInt8]) -> Int {
        written.append(bytes)
        return bytes.count
    }

    func readAvailable(maxLength: Int) -> [UInt8] {
        guard !incoming.isEmpty else { return [] }
        return incoming.removeFirst()
    }
}

@Test("IMAP client IDLE not supported (replay)")
func imapClientIdleNotSupportedReplay() {
    let transport = ImapReplayTransport(steps: [
        .command("A0001 IDLE\r\n", fixture: "common/common.idle-not-supported.txt")
    ])

    let client = ImapClient()
    client.connect(transport: transport)

    let command = client.send(.idle)
    let response = client.waitForTagged(command.tag, maxReads: 2)

    #expect(response?.status == .bad)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP client protocol logger redacts on IDLE failure (replay)")
func imapClientProtocolLoggerRedactsOnIdleFailureReplay() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = false
    logger.redactSecrets = true
    logger.clientPrefix = "C: "
    logger.serverPrefix = "S: "

    let transport = ImapReplayTransport(steps: [
        .command("A0001 LOGIN bob secret\r\n", fixture: "common/common.login-capability-no-idle.txt"),
        .command("A0002 IDLE\r\n", fixture: "common/common.idle-not-supported.txt")
    ])

    let client = ImapClient(protocolLogger: logger)
    client.connect(transport: transport)

    let loginCommand = client.send(.login("bob", "secret"))
    _ = client.waitForTagged(loginCommand.tag, maxReads: 2)

    let idleCommand = client.send(.idle)
    let idleResponse = client.waitForTagged(idleCommand.tag, maxReads: 2)

    logger.close()
    stream.close()

    let output = memoryStreamOutput(stream)
    #expect(output.contains("C: A0001 LOGIN ******** ********"))
    #expect(output.contains("S: A0002 BAD IDLE not supported."))
    #expect(!output.contains("bob"))
    #expect(!output.contains("secret"))
    #expect(idleResponse?.status == .bad)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP client NOTIFY not supported (replay)")
func imapClientNotifyNotSupportedReplay() {
    let transport = ImapReplayTransport(steps: [
        .command("A0001 NOTIFY NONE\r\n", fixture: "common/common.notify-not-supported.txt")
    ])

    let client = ImapClient()
    client.connect(transport: transport)

    let command = client.send(.notify("NONE"))
    let response = client.waitForTagged(command.tag, maxReads: 2)

    #expect(response?.status == .bad)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP client protocol logger redacts on NOTIFY failure (replay)")
func imapClientProtocolLoggerRedactsOnNotifyFailureReplay() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = false
    logger.redactSecrets = true
    logger.clientPrefix = "C: "
    logger.serverPrefix = "S: "

    let transport = ImapReplayTransport(steps: [
        .command("A0001 LOGIN bob secret\r\n", fixture: "common/common.login-capability-no-notify.txt"),
        .command("A0002 NOTIFY NONE\r\n", fixture: "common/common.notify-not-supported.txt")
    ])

    let client = ImapClient(protocolLogger: logger)
    client.connect(transport: transport)

    let loginCommand = client.send(.login("bob", "secret"))
    _ = client.waitForTagged(loginCommand.tag, maxReads: 2)

    let notifyCommand = client.send(.notify("NONE"))
    let notifyResponse = client.waitForTagged(notifyCommand.tag, maxReads: 2)

    logger.close()
    stream.close()

    let output = memoryStreamOutput(stream)
    #expect(output.contains("C: A0001 LOGIN ******** ********"))
    #expect(output.contains("S: A0002 BAD NOTIFY not supported."))
    #expect(!output.contains("bob"))
    #expect(!output.contains("secret"))
    #expect(notifyResponse?.status == .bad)
    #expect(transport.failures.isEmpty)
}

@Test("IMAP client uses synchronized literals without LITERAL+ capability")
func imapClientUsesSynchronizedLiteralWithoutCapability() {
    let transport = SyncLiteralContinuationTransport(incoming: [
        Array("+ Ready for literal\r\n".utf8)
    ])

    let client = ImapClient()
    client.connect(transport: transport)

    _ = client.send(.login("user\r\nname", "secret"))

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [
        "A0001 LOGIN {10}\r\n",
        "user\r\nname",
        " secret\r\n"
    ])

    let continuation = client.receive()
    #expect(continuation.first?.kind == .continuation)
}

@Test("IMAP client does not split literal marker text inside quoted command arguments")
func imapClientDoesNotSplitQuotedLiteralMarkerText() {
    let transport = SyncLiteralContinuationTransport()
    let client = ImapClient()
    client.connect(transport: transport)
    _ = client.handleIncomingWithLiterals(Array("* CAPABILITY IMAP4rev1 LITERAL+\r\n".utf8))

    let command = ImapCommand(tag: "A0001", name: "XTEST", arguments: "\"fake {3}\r\nabc text\"")
    _ = client.send(command)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [command.serialized])
}

@Test("IMAP client uses non-synchronizing literals with LITERAL+ capability")
func imapClientUsesNonSynchronizingLiteralWithCapability() {
    let transport = SyncLiteralContinuationTransport()
    let client = ImapClient()
    client.connect(transport: transport)
    _ = client.handleIncomingWithLiterals(Array("* CAPABILITY IMAP4rev1 LITERAL+\r\n".utf8))

    _ = client.send(.login("user\r\nname", "secret"))

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [
        "A0001 LOGIN {10+}\r\n",
        "user\r\nname",
        " secret\r\n"
    ])
}

@Test("IMAP client uses synchronized literals for LITERAL- payloads over 4096 bytes")
func imapClientUsesSynchronizedLiteralWithLiteralMinusAbove4096() {
    let transport = SyncLiteralContinuationTransport(incoming: [
        Array("+ Ready for literal\r\n".utf8)
    ])
    let client = ImapClient()
    client.connect(transport: transport)
    _ = client.handleIncomingWithLiterals(Array("* CAPABILITY IMAP4rev1 LITERAL-\r\n".utf8))

    let oversized = String(repeating: "a", count: 4096) + "\n"
    _ = client.send(.login(oversized, "secret"))

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.first == "A0001 LOGIN {4097}\r\n")

    let continuation = client.receive()
    #expect(continuation.first?.kind == .continuation)
}

@Test("IMAP client uses non-synchronizing literals for LITERAL- payloads up to 4096 bytes")
func imapClientUsesNonSynchronizingLiteralWithLiteralMinusAt4096() {
    let transport = SyncLiteralContinuationTransport()
    let client = ImapClient()
    client.connect(transport: transport)
    _ = client.handleIncomingWithLiterals(Array("* CAPABILITY IMAP4rev1 LITERAL-\r\n".utf8))

    let bounded = String(repeating: "a", count: 4095) + "\n"
    _ = client.send(.login(bounded, "secret"))

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.first == "A0001 LOGIN {4096+}\r\n")
}

@Test("IMAP client stops literal upload when server rejects before continuation")
func imapClientStopsLiteralUploadOnTaggedRejection() {
    let transport = SyncLiteralContinuationTransport(incoming: [
        Array("A0001 BAD Literal rejected\r\n".utf8)
    ])

    let client = ImapClient()
    client.connect(transport: transport)

    let command = client.send(.login("user\r\nname", "secret"))
    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == ["A0001 LOGIN {10}\r\n"])
    #expect(client.lastWriteSucceeded == true)

    let response = client.waitForTagged(command.tag, maxReads: 2)
    #expect(response?.status == .bad)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client IDLE not supported")
func asyncImapClientIdleNotSupported() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let command = try await client.send(.idle)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.last ?? [], as: UTF8.self).contains("IDLE"))

    await transport.yieldIncoming(Array("\(command.tag) BAD IDLE not supported.\r\n".utf8))
    let response = await client.waitForTagged(command.tag)
    #expect(response?.status == .bad)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client uses synchronized literals without LITERAL+ capability")
func asyncImapClientUsesSynchronizedLiteralWithoutCapability() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let sendTask = Task { try await client.send(.login("user\r\nname", "secret")) }
    guard await awaitSentCommand(transport: transport, contains: "LOGIN {10}\r\n") != nil else {
        #expect(Bool(false), "Missing synchronized literal LOGIN header")
        sendTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("+ Ready for literal\r\n".utf8))
    _ = try await sendTask.value

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [
        "A0001 LOGIN {10}\r\n",
        "user\r\nname",
        " secret\r\n"
    ])

    let messages = await client.nextMessages()
    #expect(messages.first?.response?.kind == .continuation)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client does not split literal marker text inside quoted command arguments")
func asyncImapClientDoesNotSplitQuotedLiteralMarkerText() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 LITERAL+\r\n".utf8))
    _ = await client.nextMessages()

    let command = ImapCommand(tag: "A0001", name: "XTEST", arguments: "\"fake {3}\r\nabc text\"")
    _ = try await client.send(command)

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [command.serialized])

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client uses non-synchronizing literals with LITERAL+ capability")
func asyncImapClientUsesNonSynchronizingLiteralWithCapability() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 LITERAL+\r\n".utf8))
    _ = await client.nextMessages()

    _ = try await client.send(.login("user\r\nname", "secret"))
    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == [
        "A0001 LOGIN {10+}\r\n",
        "user\r\nname",
        " secret\r\n"
    ])

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client uses synchronized literals for LITERAL- payloads over 4096 bytes")
func asyncImapClientUsesSynchronizedLiteralWithLiteralMinusAbove4096() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 LITERAL-\r\n".utf8))
    _ = await client.nextMessages()

    let oversized = String(repeating: "a", count: 4096) + "\n"
    let sendTask = Task { try await client.send(.login(oversized, "secret")) }
    guard await awaitSentCommand(transport: transport, contains: "LOGIN {4097}\r\n") != nil else {
        #expect(Bool(false), "Missing synchronized literal LOGIN header for LITERAL- > 4096")
        sendTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("+ Ready for literal\r\n".utf8))
    _ = try await sendTask.value

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.first == "A0001 LOGIN {4097}\r\n")

    let messages = await client.nextMessages()
    #expect(messages.first?.response?.kind == .continuation)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client uses non-synchronizing literals for LITERAL- payloads up to 4096 bytes")
func asyncImapClientUsesNonSynchronizingLiteralWithLiteralMinusAt4096() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 LITERAL-\r\n".utf8))
    _ = await client.nextMessages()

    let bounded = String(repeating: "a", count: 4095) + "\n"
    _ = try await client.send(.login(bounded, "secret"))

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.first == "A0001 LOGIN {4096+}\r\n")

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client stops literal upload when server rejects before continuation")
func asyncImapClientStopsLiteralUploadOnTaggedRejection() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let sendTask = Task { try await client.send(.login("user\r\nname", "secret")) }
    guard await awaitSentCommand(transport: transport, contains: "LOGIN {10}\r\n") != nil else {
        #expect(Bool(false), "Missing synchronized literal LOGIN header")
        sendTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("A0001 BAD Literal rejected\r\n".utf8))
    let command = try await sendTask.value

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent == ["A0001 LOGIN {10}\r\n"])

    let response = await client.waitForTagged(command.tag)
    #expect(response?.status == .bad)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client NOTIFY not supported")
func asyncImapClientNotifyNotSupported() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let command = try await client.send(.notify("NONE"))
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.last ?? [], as: UTF8.self).contains("NOTIFY"))

    await transport.yieldIncoming(Array("\(command.tag) BAD NOTIFY not supported.\r\n".utf8))
    let response = await client.waitForTagged(command.tag)
    #expect(response?.status == .bad)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client AUTHENTICATE challenge refreshes capabilities")
func asyncImapClientAuthenticateChallengeRefreshesCapabilities() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let auth = ImapSasl.login(username: "bob", password: "secret", useInitialResponse: false)
    let authenticateTask = Task { try await client.authenticate(auth) }

    guard let authenticateLine = await awaitSentCommand(transport: transport, contains: "AUTHENTICATE LOGIN") else {
        #expect(Bool(false), "Missing AUTHENTICATE command")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    guard let authenticateTag = extractTag(from: authenticateLine) else {
        #expect(Bool(false), "Missing AUTHENTICATE tag")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("+ VXNlcm5hbWU6\r\n".utf8))
    guard await awaitSentCommand(transport: transport, contains: "Ym9i\r\n") != nil else {
        #expect(Bool(false), "Missing encoded username response")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("+ UGFzc3dvcmQ6\r\n".utf8))
    guard await awaitSentCommand(transport: transport, contains: "c2VjcmV0\r\n") != nil else {
        #expect(Bool(false), "Missing encoded password response")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("\(authenticateTag) OK AUTHENTICATE completed\r\n".utf8))

    guard let capabilityLine = await awaitSentCommand(transport: transport, contains: " CAPABILITY\r\n") else {
        #expect(Bool(false), "Missing CAPABILITY refresh command")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    guard let capabilityTag = extractTag(from: capabilityLine) else {
        #expect(Bool(false), "Missing CAPABILITY tag")
        authenticateTask.cancel()
        await client.stop()
        return
    }

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 IDLE\r\n".utf8))
    await transport.yieldIncoming(Array("\(capabilityTag) OK CAPABILITY completed\r\n".utf8))

    let response = try await authenticateTask.value
    #expect(response?.status == .ok)
    #expect(await client.state == .authenticated)
    #expect(await client.capabilities?.supports("IDLE") == true)

    let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains(where: { $0.contains("AUTHENTICATE LOGIN") }))
    #expect(sent.contains(where: { $0.contains(" CAPABILITY\r\n") }))

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client protocol logger redacts on IDLE failure")
func asyncImapClientProtocolLoggerRedactsOnIdleFailure() async throws {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = false
    logger.redactSecrets = true
    logger.clientPrefix = "C: "
    logger.serverPrefix = "S: "

    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()
    await client.setProtocolLogger(logger)

    let loginTask = Task { try await client.login(user: "bob", password: "secret") }
    guard let loginLine = await awaitSentCommand(transport: transport, contains: "LOGIN") else {
        #expect(Bool(false), "Missing LOGIN command")
        loginTask.cancel()
        await client.stop()
        stream.close()
        return
    }

    guard let loginTag = extractTag(from: loginLine) else {
        #expect(Bool(false), "Missing LOGIN tag")
        loginTask.cancel()
        await client.stop()
        stream.close()
        return
    }
    await transport.yieldIncoming(Array("\(loginTag) OK [CAPABILITY IMAP4rev1] Logged in\r\n".utf8))
    let loginResponse = try await loginTask.value
    #expect(loginResponse?.status == .ok)

    let idleCommand = try await client.send(.idle)
    await transport.yieldIncoming(Array("\(idleCommand.tag) BAD IDLE not supported.\r\n".utf8))
    let idleResponse = await client.waitForTagged(idleCommand.tag)
    #expect(idleResponse?.status == .bad)

    await client.stop()
    stream.close()

    let output = memoryStreamOutput(stream)
    #expect(output.contains("C: \(loginTag) LOGIN ******** ********"))
    #expect(output.contains("S: \(idleCommand.tag) BAD IDLE not supported."))
    #expect(!output.contains("bob"))
    #expect(!output.contains("secret"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP client protocol logger redacts on NOTIFY failure")
func asyncImapClientProtocolLoggerRedactsOnNotifyFailure() async throws {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = false
    logger.redactSecrets = true
    logger.clientPrefix = "C: "
    logger.serverPrefix = "S: "

    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()
    await client.setProtocolLogger(logger)

    let loginTask = Task { try await client.login(user: "bob", password: "secret") }
    guard let loginLine = await awaitSentCommand(transport: transport, contains: "LOGIN") else {
        #expect(Bool(false), "Missing LOGIN command")
        loginTask.cancel()
        await client.stop()
        stream.close()
        return
    }

    guard let loginTag = extractTag(from: loginLine) else {
        #expect(Bool(false), "Missing LOGIN tag")
        loginTask.cancel()
        await client.stop()
        stream.close()
        return
    }
    await transport.yieldIncoming(Array("\(loginTag) OK [CAPABILITY IMAP4rev1] Logged in\r\n".utf8))
    let loginResponse = try await loginTask.value
    #expect(loginResponse?.status == .ok)

    let notifyCommand = try await client.send(.notify("NONE"))
    await transport.yieldIncoming(Array("\(notifyCommand.tag) BAD NOTIFY not supported.\r\n".utf8))
    let notifyResponse = await client.waitForTagged(notifyCommand.tag)
    #expect(notifyResponse?.status == .bad)

    await client.stop()
    stream.close()

    let output = memoryStreamOutput(stream)
    #expect(output.contains("C: \(loginTag) LOGIN ******** ********"))
    #expect(output.contains("S: \(notifyCommand.tag) BAD NOTIFY not supported."))
    #expect(!output.contains("bob"))
    #expect(!output.contains("secret"))
}
