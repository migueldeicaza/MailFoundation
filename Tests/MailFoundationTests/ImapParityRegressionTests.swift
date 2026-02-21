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

private class ParitySyncTransport: Transport {
    var incoming: [[UInt8]]
    var written: [[UInt8]] = []
    var isConnected: Bool { true }

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

private final class ParitySyncStartTlsTransport: ParitySyncTransport, StartTlsTransport {
    var startTlsValidations: [Bool] = []
    var scramChannelBinding: ScramChannelBinding? { nil }

    func startTLS(validateCertificate: Bool) {
        startTlsValidations.append(validateCertificate)
    }
}

private final class ParitySyncDisconnectingTransport: ParitySyncTransport {
    private var connected = true
    override var isConnected: Bool { connected }

    override func open() {
        connected = true
    }

    override func close() {
        connected = false
    }

    override func readAvailable(maxLength: Int) -> [UInt8] {
        guard connected else { return [] }
        guard !incoming.isEmpty else {
            connected = false
            return []
        }
        return incoming.removeFirst()
    }
}

@available(macOS 10.15, iOS 13.0, *)
private actor ParityAsyncStartTlsTransport: AsyncStartTlsTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var started = false
    private var sent: [[UInt8]] = []
    private var startTlsValidations: [Bool] = []
    var scramChannelBinding: ScramChannelBinding? { get async { nil } }

    init() {
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    func start() async throws {
        started = true
    }

    func stop() async {
        started = false
        continuation.finish()
    }

    func send(_ bytes: [UInt8]) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        sent.append(bytes)
    }

    func startTLS(validateCertificate: Bool) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        startTlsValidations.append(validateCertificate)
    }

    func yieldIncoming(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    func sentSnapshot() -> [[UInt8]] {
        sent
    }

    func startTlsValidationSnapshot() -> [Bool] {
        startTlsValidations
    }
}

struct ImapParityRegressionTests {
    @Test("IMAP LOGIN serialization uses literals for CRLF/NUL credentials")
    func imapLoginSerializationUsesLiteralForUnsafeScalars() {
        let serialized = ImapCommandKind
            .login("user\r\nname", "pa\u{0}\"\\ss")
            .command(tag: "A1")
            .serialized

        let expected = Array("A1 LOGIN {10+}\r\nuser\r\nname {7+}\r\npa".utf8) +
            [0] +
            Array("\"\\ss\r\n".utf8)
        #expect(Array(serialized.utf8) == expected)
    }

    @Test("Sync IMAP STARTTLS triggers CAPABILITY refresh when unchanged")
    func syncImapStartTlsRefreshesCapabilitiesWhenUnchanged() throws {
        let transport = ParitySyncStartTlsTransport(incoming: [
            Array("* OK [CAPABILITY IMAP4rev1 STARTTLS] Ready\r\n".utf8),
            Array("A0001 OK Begin TLS\r\n".utf8),
            Array("* CAPABILITY IMAP4rev1 STARTTLS IDLE\r\n".utf8),
            Array("A0002 OK CAPABILITY completed\r\n".utf8)
        ])

        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        let response = try session.startTls(validateCertificate: false)

        #expect(response.isOk)
        #expect(transport.startTlsValidations == [false])

        let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
        #expect(sent == ["A0001 STARTTLS\r\n", "A0002 CAPABILITY\r\n"])
        #expect(session.capabilities?.supports("IDLE") == true)
    }

    @Test("Sync IMAP blocks command traffic while IDLE is active")
    func syncImapIdleExclusivityBlocksOtherCommands() throws {
        let transport = ParitySyncTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "IDLE"]),
            Array("* 1 EXISTS\r\n".utf8),
            Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8),
            Array("+ idling\r\n".utf8),
            Array("* 2 EXISTS\r\n".utf8),
            Array("A0003 OK IDLE terminated\r\n".utf8)
        ])

        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        _ = try session.select(mailbox: "INBOX")
        _ = try session.startIdle()

        do {
            _ = try session.noop()
            #expect(Bool(false), "NOOP should fail while IDLE is active")
        } catch let error as SessionError {
            if case .imapError(let status, let text) = error {
                #expect(status == .bad)
                #expect(text == "IDLE command is active.")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }

        let events = session.readIdleEvents(maxReads: 2)
        #expect(events == [.exists(2)])

        try session.stopIdle()

        let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
        #expect(sent.contains("DONE\r\n"))
        #expect(sent.contains(where: { $0.contains(" NOOP") }) == false)
    }

    @Test("Sync IMAP UID SEARCH preserves unsolicited selected-state updates")
    func syncImapUidSearchPreservesUnsolicitedSelectedStateUpdates() throws {
        let transport = ParitySyncTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1"]),
            Array("* 5 EXISTS\r\n".utf8),
            Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8),
            Array("* 42 EXISTS\r\n".utf8),
            Array("* 5 FETCH (FLAGS (\\Seen \\Recent))\r\n".utf8),
            Array("* SEARCH 101 102\r\n".utf8),
            Array("A0003 OK UID SEARCH completed\r\n".utf8)
        ])

        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        _ = try session.select(mailbox: "INBOX")

        let result = try session.uidSearch("ALL")
        #expect(result.ids == [101, 102])
        #expect(session.selectedState.messageCount == 42)

        let events = session.readIdleEvents(maxReads: 4)
        #expect(events == [
            .exists(42),
            .other("* 5 FETCH (FLAGS (\\Seen \\Recent))")
        ])
    }

    @Test("Sync IMAP ENABLE applies QRESYNC fallback when ENABLED is omitted")
    func syncImapEnableQresyncFallbackWithoutEnabledResponse() throws {
        let transport = ParitySyncTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "ENABLE", "QRESYNC", "CONDSTORE"]),
            Array("A0002 OK ENABLE completed\r\n".utf8)
        ])

        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        let enabled = try session.enable(["QRESYNC", "CONDSTORE"])

        #expect(enabled.contains(where: { $0.uppercased() == "QRESYNC" }))
        #expect(enabled.contains(where: { $0.uppercased() == "CONDSTORE" }))
    }

    @Test("Sync IMAP ENABLE requires authenticated state (not selected)")
    func syncImapEnableRequiresAuthenticatedState() throws {
        let transport = ParitySyncTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "ENABLE", "QRESYNC", "CONDSTORE"]),
            Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8)
        ])

        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        _ = try session.select(mailbox: "INBOX")

        do {
            _ = try session.enable(["QRESYNC", "CONDSTORE"])
            #expect(Bool(false), "ENABLE should fail in selected state")
        } catch let error as SessionError {
            if case .invalidImapState(let expected, let actual) = error {
                #expect(expected == .authenticated)
                #expect(actual == .selected)
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }

        let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
        #expect(sent == ["A0001 LOGIN user pass\r\n", "A0002 SELECT INBOX\r\n"])
    }

    @Test("Sync IMAP fetch surfaces connection closed when transport drops")
    func syncImapFetchDropThrowsConnectionClosed() throws {
        let transport = ParitySyncDisconnectingTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1"]),
            Array("* 1 EXISTS\r\n".utf8),
            Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8),
            Array("* 1 FETCH (UID 1 FLAGS (\\Seen))\r\n".utf8)
        ])
        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        _ = try session.select(mailbox: "INBOX")

        do {
            _ = try session.fetchWithQresync("1", items: "(UID FLAGS)")
            #expect(Bool(false), "FETCH should fail when the transport disconnects before tagged completion")
        } catch let error as SessionError {
            if case .connectionClosed(let message) = error {
                #expect(message == "Connection closed by server.")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }
    }

    @Test("Sync IMAP IDLE start surfaces connection closed when transport drops")
    func syncImapStartIdleDropThrowsConnectionClosed() throws {
        let transport = ParitySyncDisconnectingTransport(incoming: [
            Array("* OK Ready\r\n".utf8),
            ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "IDLE"]),
            Array("* 1 EXISTS\r\n".utf8),
            Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8)
        ])
        let session = ImapSession(transport: transport, maxReads: 8)
        _ = try session.connect()
        _ = try session.login(user: "user", password: "pass")
        _ = try session.select(mailbox: "INBOX")

        do {
            _ = try session.startIdle()
            #expect(Bool(false), "IDLE should fail when the transport disconnects before continuation")
        } catch let error as SessionError {
            if case .connectionClosed(let message) = error {
                #expect(message == "Connection closed by server.")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP connect rejects BYE greeting")
    func asyncImapConnectRejectsByeGreeting() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* BYE Server unavailable\r\n".utf8))

        do {
            _ = try await connectTask.value
            #expect(Bool(false), "Connect should fail on BYE greeting")
        } catch let error as SessionError {
            if case .imapError(let status, let text) = error {
                #expect(status == .bye)
                #expect(text == "Server unavailable")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP STARTTLS triggers CAPABILITY refresh when unchanged")
    func asyncImapStartTlsRefreshesCapabilitiesWhenUnchanged() async throws {
        let transport = ParityAsyncStartTlsTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK [CAPABILITY IMAP4rev1 STARTTLS] Ready\r\n".utf8))
        _ = try await connectTask.value

        let startTlsTask = Task { try await session.startTls(validateCertificate: false) }
        await transport.yieldIncoming(Array("A0001 OK Begin TLS\r\n".utf8))
        await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 STARTTLS IDLE\r\n".utf8))
        await transport.yieldIncoming(Array("A0002 OK CAPABILITY completed\r\n".utf8))

        let response = try await startTlsTask.value
        #expect(response.isOk)
        #expect(await transport.startTlsValidationSnapshot() == [false])

        let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
        #expect(sent == ["A0001 STARTTLS\r\n", "A0002 CAPABILITY\r\n"])
        #expect(await session.capabilities?.supports("IDLE") == true)
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP blocks command traffic while IDLE is active")
    func asyncImapIdleExclusivityBlocksOtherCommands() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "IDLE"]))
        _ = try await loginTask.value

        let selectTask = Task { try await session.select(mailbox: "INBOX") }
        await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
        await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
        _ = try await selectTask.value

        let idleTask = Task { try await session.startIdle() }
        await transport.yieldIncoming(Array("+ idling\r\n".utf8))
        _ = try await idleTask.value

        do {
            _ = try await session.noop()
            #expect(Bool(false), "NOOP should fail while IDLE is active")
        } catch let error as SessionError {
            if case .imapError(let status, let text) = error {
                #expect(status == .bad)
                #expect(text == "IDLE command is active.")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }

        await transport.yieldIncoming(Array("* 2 EXISTS\r\n".utf8))
        let events = try await session.readIdleEvents(maxEmptyReads: 2)
        #expect(events == [.exists(2)])

        let stopIdleTask = Task { try await session.stopIdle() }
        await transport.yieldIncoming(Array("A0003 OK IDLE terminated\r\n".utf8))
        _ = try await stopIdleTask.value

        let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
        #expect(sent.contains("DONE\r\n"))
        #expect(sent.contains(where: { $0.contains(" NOOP") }) == false)
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP UID SEARCH preserves unsolicited selected-state updates")
    func asyncImapUidSearchPreservesUnsolicitedSelectedStateUpdates() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1"]))
        _ = try await loginTask.value

        let selectTask = Task { try await session.select(mailbox: "INBOX") }
        await transport.yieldIncoming(Array("* 5 EXISTS\r\n".utf8))
        await transport.yieldIncoming(Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8))
        _ = try await selectTask.value

        let searchTask = Task { try await session.uidSearch("ALL") }
        await transport.yieldIncoming(Array("* 42 EXISTS\r\n".utf8))
        await transport.yieldIncoming(Array("* 5 FETCH (FLAGS (\\Seen \\Recent))\r\n".utf8))
        await transport.yieldIncoming(Array("* SEARCH 101 102\r\n".utf8))
        await transport.yieldIncoming(Array("A0003 OK UID SEARCH completed\r\n".utf8))
        let result = try await searchTask.value

        #expect(result.ids == [101, 102])
        #expect(await session.selectedState.messageCount == 42)

        let events = try await session.readIdleEvents(maxEmptyReads: 1)
        #expect(events == [
            .exists(42),
            .other("* 5 FETCH (FLAGS (\\Seen \\Recent))")
        ])
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP ENABLE applies QRESYNC fallback when ENABLED is omitted")
    func asyncImapEnableQresyncFallbackWithoutEnabledResponse() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "ENABLE", "QRESYNC", "CONDSTORE"]))
        _ = try await loginTask.value

        let enableTask = Task { try await session.enable(["QRESYNC", "CONDSTORE"]) }
        await transport.yieldIncoming(Array("A0002 OK ENABLE completed\r\n".utf8))
        let enabled = try await enableTask.value

        #expect(enabled.contains(where: { $0.uppercased() == "QRESYNC" }))
        #expect(enabled.contains(where: { $0.uppercased() == "CONDSTORE" }))
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP ENABLE requires authenticated state (not selected)")
    func asyncImapEnableRequiresAuthenticatedState() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "ENABLE", "QRESYNC", "CONDSTORE"]))
        _ = try await loginTask.value

        let selectTask = Task { try await session.select(mailbox: "INBOX") }
        await transport.yieldIncoming(Array("A0002 OK [READ-WRITE] SELECT completed\r\n".utf8))
        _ = try await selectTask.value

        do {
            _ = try await session.enable(["QRESYNC", "CONDSTORE"])
            #expect(Bool(false), "ENABLE should fail in selected state")
        } catch let error as SessionError {
            if case .invalidImapState(let expected, let actual) = error {
                #expect(expected == .authenticated)
                #expect(actual == .selected)
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }

        let sent = await transport.sentSnapshot().map { String(decoding: $0, as: UTF8.self) }
        #expect(sent == ["A0001 LOGIN user pass\r\n", "A0002 SELECT INBOX\r\n"])
    }

    @available(macOS 10.15, iOS 13.0, *)
    @Test("Async IMAP IDLE start surfaces connection closed when transport drops")
    func asyncImapStartIdleDropThrowsConnectionClosed() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "IDLE"]))
        _ = try await loginTask.value

        let selectTask = Task { try await session.select(mailbox: "INBOX") }
        await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
        await transport.yieldIncoming(Array("A0002 OK SELECT completed\r\n".utf8))
        _ = try await selectTask.value

        let idleTask = Task { try await session.startIdle(maxEmptyReads: 1_000) }
        try await Task.sleep(nanoseconds: 10_000_000)
        await transport.stop()

        do {
            _ = try await idleTask.value
            #expect(Bool(false), "IDLE should fail when the transport disconnects before continuation")
        } catch let error as SessionError {
            if case .connectionClosed(let message) = error {
                #expect(message == "Connection closed by server.")
            } else {
                #expect(Bool(false), "Unexpected SessionError: \(error)")
            }
        }
    }
}
