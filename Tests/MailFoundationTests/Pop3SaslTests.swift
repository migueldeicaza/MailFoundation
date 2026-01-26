import Testing
@testable import MailFoundation

@Test("POP3 CAPA SASL mechanisms parsing")
func pop3CapabilitiesSaslMechanisms() {
    let capabilities = Pop3Capabilities(rawLines: [
        "SASL PLAIN LOGIN",
        "PIPELINING"
    ])
    #expect(capabilities.saslMechanisms() == ["PLAIN", "LOGIN"])
}

@Test("POP3 SASL mechanism selection")
func pop3SaslMechanismSelection() {
    #if canImport(CryptoKit)
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "pass",
        mechanisms: ["CRAM-MD5", "LOGIN", "PLAIN"]
    )
    #expect(auth?.mechanism == "CRAM-MD5")
    #else
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "pass",
        mechanisms: ["LOGIN", "PLAIN"]
    )
    #expect(auth?.mechanism == "PLAIN")
    #endif
}

@Test("POP3 SASL CRAM-MD5 response")
func pop3SaslCramMd5Response() throws {
    #if canImport(CryptoKit)
    guard let auth = Pop3Sasl.cramMd5(username: "tim", password: "tanstaaftanstaaf") else {
        return
    }
    let challenge = "PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+"
    let response = try auth.responder?(challenge)
    #expect(response == "dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw")
    #else
    return
    #endif
}

@Test("POP3 SASL XOAUTH2 initial response")
func pop3SaslXoauth2Response() {
    let auth = Pop3Sasl.xoauth2(username: "user@example.com", accessToken: "token")
    #expect(auth.mechanism == "XOAUTH2")
    #expect(auth.initialResponse == Pop3Sasl.base64("user=user@example.com\u{01}auth=Bearer token\u{01}\u{01}"))
}

@Test("Sync POP3 SASL PLAIN authentication")
func syncPop3SaslPlain() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Authenticated\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 2)
    _ = try session.connect()

    let response = try session.authenticateSasl(
        user: "user",
        password: "pass",
        mechanisms: ["PLAIN"]
    )
    #expect(response.isSuccess)

    let expected = "AUTH PLAIN \(Pop3Sasl.plain(username: "user", password: "pass").initialResponse ?? "")\r\n"
    let sent = String(decoding: transport.written.first ?? [], as: UTF8.self)
    #expect(sent == expected)
}

@Test("Sync POP3 SASL CRAM-MD5 authentication")
func syncPop3SaslCramMd5() throws {
    #if canImport(CryptoKit)
    let challenge = "PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+"
    let expectedResponse = "dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw"
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+ \(challenge)\r\n".utf8),
        Array("+OK Authenticated\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()

    let response = try session.authenticateCramMd5(user: "tim", password: "tanstaaftanstaaf")
    #expect(response.isSuccess)

    let first = String(decoding: transport.written.first ?? [], as: UTF8.self)
    let second = String(decoding: transport.written.dropFirst().first ?? [], as: UTF8.self)
    #expect(first == "AUTH CRAM-MD5\r\n")
    #expect(second == "\(expectedResponse)\r\n")
    #else
    return
    #endif
}

@Test("Sync POP3 SASL XOAUTH2 authentication")
func syncPop3SaslXoauth2() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Authenticated\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 2)
    _ = try session.connect()

    let response = try session.authenticateXoauth2(user: "user@example.com", accessToken: "token")
    #expect(response.isSuccess)

    let expected = "AUTH XOAUTH2 \(Pop3Sasl.xoauth2(username: "user@example.com", accessToken: "token").initialResponse ?? "")\r\n"
    let sent = String(decoding: transport.written.first ?? [], as: UTF8.self)
    #expect(sent == expected)
}

@Test("Sync POP3 SASL CRAM-MD5 via CAPA")
func syncPop3SaslCramMd5ViaCapa() throws {
    #if canImport(CryptoKit)
    let challenge = "PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+"
    let expectedResponse = "dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw"
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Capability list follows\r\nSASL CRAM-MD5 PLAIN\r\n.\r\n".utf8),
        Array("+ \(challenge)\r\n".utf8),
        Array("+OK Authenticated\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 5)
    _ = try session.connect()

    let response = try session.authenticateSasl(user: "tim", password: "tanstaaftanstaaf")
    #expect(response.isSuccess)

    let first = String(decoding: transport.written.first ?? [], as: UTF8.self)
    let second = String(decoding: transport.written.dropFirst().first ?? [], as: UTF8.self)
    let third = String(decoding: transport.written.dropFirst(2).first ?? [], as: UTF8.self)
    #expect(first == "CAPA\r\n")
    #expect(second == "AUTH CRAM-MD5\r\n")
    #expect(third == "\(expectedResponse)\r\n")
    #else
    return
    #endif
}

@Test("Sync POP3 SASL XOAUTH2 via CAPA")
func syncPop3SaslXoauth2ViaCapa() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Capability list follows\r\nSASL XOAUTH2\r\n.\r\n".utf8),
        Array("+OK Authenticated\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()

    let response = try session.authenticateSasl(user: "user@example.com", accessToken: "token")
    #expect(response.isSuccess)

    let first = String(decoding: transport.written.first ?? [], as: UTF8.self)
    let second = String(decoding: transport.written.dropFirst().first ?? [], as: UTF8.self)
    #expect(first == "CAPA\r\n")
    #expect(second == "AUTH XOAUTH2 \(Pop3Sasl.xoauth2(username: "user@example.com", accessToken: "token").initialResponse ?? "")\r\n")
}

@Test("Sync POP3 SASL XOAUTH2 via CAPA unsupported")
func syncPop3SaslXoauth2ViaCapaUnsupported() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Capability list follows\r\nSASL PLAIN\r\n.\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()

    #expect(throws: SessionError.pop3Error(message: "XOAUTH2 is not supported.")) {
        _ = try session.authenticateSasl(user: "user@example.com", accessToken: "token")
    }
}

@Test("Sync POP3 SASL CRAM-MD5 via CAPA unsupported")
func syncPop3SaslCramMd5ViaCapaUnsupported() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK Capability list follows\r\nSASL XOAUTH2\r\n.\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()

    #expect(throws: SessionError.pop3Error(message: "No supported SASL mechanisms.")) {
        _ = try session.authenticateSasl(user: "user", password: "pass")
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL PLAIN authentication")
func asyncPop3SaslPlain() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task {
        try await session.authenticateSasl(
            user: "user",
            password: "pass",
            mechanisms: ["PLAIN"]
        )
    }
    await transport.yieldIncoming(Array("+OK Authenticated\r\n".utf8))
    _ = try await authTask.value

    let sent = await transport.sentSnapshot()
    let expected = "AUTH PLAIN \(Pop3Sasl.plain(username: "user", password: "pass").initialResponse ?? "")\r\n"
    let serialized = String(decoding: sent.last ?? [], as: UTF8.self)
    #expect(serialized == expected)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL CRAM-MD5 authentication")
func asyncPop3SaslCramMd5() async throws {
    #if canImport(CryptoKit)
    let challenge = "PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+"
    let expectedResponse = "dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw"
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task { try await session.authenticateCramMd5(user: "tim", password: "tanstaaftanstaaf") }
    await transport.yieldIncoming(Array("+ \(challenge)\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Authenticated\r\n".utf8))
    _ = try await authTask.value

    let sent = await transport.sentSnapshot()
    let first = String(decoding: sent.first ?? [], as: UTF8.self)
    let second = String(decoding: sent.dropFirst().first ?? [], as: UTF8.self)
    #expect(first == "AUTH CRAM-MD5\r\n")
    #expect(second == "\(expectedResponse)\r\n")
    #else
    return
    #endif
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL XOAUTH2 authentication")
func asyncPop3SaslXoauth2() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task {
        try await session.authenticateXoauth2(user: "user@example.com", accessToken: "token")
    }
    await transport.yieldIncoming(Array("+OK Authenticated\r\n".utf8))
    _ = try await authTask.value

    let sent = await transport.sentSnapshot()
    let expected = "AUTH XOAUTH2 \(Pop3Sasl.xoauth2(username: "user@example.com", accessToken: "token").initialResponse ?? "")\r\n"
    let serialized = String(decoding: sent.last ?? [], as: UTF8.self)
    #expect(serialized == expected)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL CRAM-MD5 via CAPA")
func asyncPop3SaslCramMd5ViaCapa() async throws {
    #if canImport(CryptoKit)
    let challenge = "PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+"
    let expectedResponse = "dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw"
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task {
        try await session.authenticateSasl(user: "tim", password: "tanstaaftanstaaf")
    }
    await transport.yieldIncoming(Array("+OK Capability list follows\r\nSASL CRAM-MD5 PLAIN\r\n.\r\n".utf8))
    await transport.yieldIncoming(Array("+ \(challenge)\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Authenticated\r\n".utf8))
    _ = try await authTask.value

    let sent = await transport.sentSnapshot()
    let first = String(decoding: sent.first ?? [], as: UTF8.self)
    let second = String(decoding: sent.dropFirst().first ?? [], as: UTF8.self)
    let third = String(decoding: sent.dropFirst(2).first ?? [], as: UTF8.self)
    #expect(first == "CAPA\r\n")
    #expect(second == "AUTH CRAM-MD5\r\n")
    #expect(third == "\(expectedResponse)\r\n")
    #else
    return
    #endif
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL XOAUTH2 via CAPA")
func asyncPop3SaslXoauth2ViaCapa() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let authTask = Task {
        try await session.authenticateSasl(user: "user@example.com", accessToken: "token")
    }
    await transport.yieldIncoming(Array("+OK Capability list follows\r\nSASL XOAUTH2\r\n.\r\n".utf8))
    await transport.yieldIncoming(Array("+OK Authenticated\r\n".utf8))
    _ = try await authTask.value

    let sent = await transport.sentSnapshot()
    let first = String(decoding: sent.first ?? [], as: UTF8.self)
    let second = String(decoding: sent.dropFirst().first ?? [], as: UTF8.self)
    #expect(first == "CAPA\r\n")
    #expect(second == "AUTH XOAUTH2 \(Pop3Sasl.xoauth2(username: "user@example.com", accessToken: "token").initialResponse ?? "")\r\n")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL XOAUTH2 via CAPA unsupported")
func asyncPop3SaslXoauth2ViaCapaUnsupported() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    await #expect(throws: SessionError.pop3Error(message: "XOAUTH2 is not supported.")) {
        let authTask = Task {
            try await session.authenticateSasl(user: "user@example.com", accessToken: "token")
        }
        await transport.yieldIncoming(Array("+OK Capability list follows\r\nSASL PLAIN\r\n.\r\n".utf8))
        _ = try await authTask.value
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 SASL CRAM-MD5 via CAPA unsupported")
func asyncPop3SaslCramMd5ViaCapaUnsupported() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    await #expect(throws: SessionError.pop3Error(message: "No supported SASL mechanisms.")) {
        let authTask = Task { try await session.authenticateSasl(user: "user", password: "pass") }
        await transport.yieldIncoming(Array("+OK Capability list follows\r\nSASL XOAUTH2\r\n.\r\n".utf8))
        _ = try await authTask.value
    }
}
