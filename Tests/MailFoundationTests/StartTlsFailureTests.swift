import Testing
@testable import MailFoundation

private enum StartTlsTestError: Error, Equatable {
    case failed
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session STARTTLS failure propagation")
func asyncSmtpSessionStartTlsFailure() async throws {
    let transport = FailingStartTlsAsyncTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    await transport.yieldIncoming(Array("220 Go ahead\r\n".utf8))

    do {
        _ = try await startTlsTask.value
        #expect(Bool(false))
    } catch let error as StartTlsTestError {
        #expect(error == .failed)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session STARTTLS failure propagation")
func asyncPop3SessionStartTlsFailure() async throws {
    let transport = FailingStartTlsAsyncTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    await transport.yieldIncoming(Array("+OK Begin TLS\r\n".utf8))

    do {
        _ = try await startTlsTask.value
        #expect(Bool(false))
    } catch let error as StartTlsTestError {
        #expect(error == .failed)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session STARTTLS failure propagation")
func asyncImapSessionStartTlsFailure() async throws {
    let transport = FailingStartTlsAsyncTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    await transport.yieldIncoming(Array("A0001 OK Begin TLS\r\n".utf8))

    do {
        _ = try await startTlsTask.value
        #expect(Bool(false))
    } catch let error as StartTlsTestError {
        #expect(error == .failed)
    }
}

@available(macOS 10.15, iOS 13.0, *)
private actor FailingStartTlsAsyncTransport: AsyncStartTlsTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var started = false

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
    }

    func startTLS(validateCertificate: Bool) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        throw StartTlsTestError.failed
    }

    func yieldIncoming(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }
}
