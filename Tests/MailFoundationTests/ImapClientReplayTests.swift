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
