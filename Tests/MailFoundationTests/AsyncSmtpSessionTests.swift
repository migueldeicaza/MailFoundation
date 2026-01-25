import Testing
@testable import MailFoundation

@available(macOS 10.15, iOS 13.0, *)
private actor ChallengeCounter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

// MARK: - Connection & EHLO

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session connects and receives greeting")
func asyncSmtpSessionConnect() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    let response = try await connectTask.value

    #expect(response?.code == 220)
    #expect(await session.isConnected == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session EHLO")
func asyncSmtpSessionEhlo() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com Hello\r\n".utf8))
    await transport.yieldIncoming(Array("250-SIZE 35882577\r\n".utf8))
    await transport.yieldIncoming(Array("250-8BITMIME\r\n".utf8))
    await transport.yieldIncoming(Array("250-PIPELINING\r\n".utf8))
    await transport.yieldIncoming(Array("250-AUTH PLAIN LOGIN\r\n".utf8))
    await transport.yieldIncoming(Array("250 STARTTLS\r\n".utf8))
    let caps = try await ehloTask.value

    #expect(caps?.supports("8BITMIME") == true)
    #expect(caps?.supports("PIPELINING") == true)
    #expect(caps?.supports("STARTTLS") == true)
    #expect(caps?.value(for: "SIZE") == "35882577")
    #expect(caps?.value(for: "AUTH")?.contains("PLAIN") == true)
    #expect(caps?.value(for: "AUTH")?.contains("LOGIN") == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session HELO fallback")
func asyncSmtpSessionHelo() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com SMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let heloTask = Task { try await session.helo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250 mail.example.com Hello client.example.com\r\n".utf8))
    let response = try await heloTask.value

    #expect(response?.code == 250)
}

// MARK: - Authentication

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session AUTH PLAIN")
func asyncSmtpSessionAuthPlain() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com Hello\r\n".utf8))
    await transport.yieldIncoming(Array("250 AUTH PLAIN LOGIN\r\n".utf8))
    _ = try await ehloTask.value

    // AUTH PLAIN with initial response
    let authTask = Task { try await session.authenticate(mechanism: "PLAIN", initialResponse: "AGFsaWNlAHNlY3JldA==") }
    await transport.yieldIncoming(Array("235 2.7.0 Authentication successful\r\n".utf8))
    let response = try await authTask.value

    #expect(response?.code == 235)
    #expect(await session.isAuthenticated == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session AUTH LOGIN with challenge-response")
func asyncSmtpSessionAuthLogin() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com Hello\r\n".utf8))
    await transport.yieldIncoming(Array("250 AUTH PLAIN LOGIN\r\n".utf8))
    _ = try await ehloTask.value

    let counter = ChallengeCounter()
    let authTask = Task {
        try await session.authenticate(mechanism: "LOGIN", initialResponse: nil) { _ in
            let count = await counter.increment()
            if count == 1 {
                return "dXNlcm5hbWU=" // base64("username")
            } else {
                return "cGFzc3dvcmQ=" // base64("password")
            }
        }
    }
    await transport.yieldIncoming(Array("334 VXNlcm5hbWU6\r\n".utf8)) // "Username:"
    await transport.yieldIncoming(Array("334 UGFzc3dvcmQ6\r\n".utf8)) // "Password:"
    await transport.yieldIncoming(Array("235 2.7.0 Authentication successful\r\n".utf8))
    let response = try await authTask.value

    #expect(response.code == 235)
    #expect(await counter.count == 2)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session authentication failure returns error response")
func asyncSmtpSessionAuthFailure() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250 AUTH PLAIN\r\n".utf8))
    _ = try await ehloTask.value

    let authTask = Task { try await session.authenticate(mechanism: "PLAIN", initialResponse: "AGJhZABjcmVkcw==") }
    await transport.yieldIncoming(Array("535 5.7.8 Authentication credentials invalid\r\n".utf8))
    let response = try await authTask.value

    // Auth returns response on failure, doesn't throw
    #expect(response?.code == 535)
    #expect(await session.isAuthenticated == false)
}

// MARK: - Sending Mail

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session MAIL FROM")
func asyncSmtpSessionMailFrom() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let mailTask = Task { try await session.mailFrom("sender@example.com") }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    let response = try await mailTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session RCPT TO")
func asyncSmtpSessionRcptTo() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let mailTask = Task { try await session.mailFrom("sender@example.com") }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    _ = try await mailTask.value

    let rcptTask = Task { try await session.rcptTo("recipient@example.com") }
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8))
    let response = try await rcptTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session DATA command")
func asyncSmtpSessionData() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let mailTask = Task { try await session.mailFrom("sender@example.com") }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    _ = try await mailTask.value

    let rcptTask = Task { try await session.rcptTo("recipient@example.com") }
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8))
    _ = try await rcptTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello, World!\r\n".utf8)
    let dataTask = Task { try await session.data(messageData) }
    await transport.yieldIncoming(Array("354 End data with <CR><LF>.<CR><LF>\r\n".utf8))
    await transport.yieldIncoming(Array("250 2.0.0 Ok: queued as ABC123\r\n".utf8))
    let response = try await dataTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session sendMail complete flow")
func asyncSmtpSessionSendMailFlow() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello!\r\n".utf8)
    let sendTask = Task {
        try await session.sendMail(
            from: "sender@example.com",
            to: ["recipient1@example.com", "recipient2@example.com"],
            data: messageData
        )
    }

    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8)) // MAIL FROM
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8)) // RCPT TO 1
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8)) // RCPT TO 2
    await transport.yieldIncoming(Array("354 End data with <CR><LF>.<CR><LF>\r\n".utf8)) // DATA
    await transport.yieldIncoming(Array("250 2.0.0 Ok: queued\r\n".utf8)) // After message

    let response = try await sendTask.value
    #expect(response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session sendMail recipient rejection")
func asyncSmtpSessionSendMailRecipientRejected() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello!\r\n".utf8)
    let sendTask = Task {
        try await session.sendMail(
            from: "sender@example.com",
            to: ["bad@example.com"],
            data: messageData
        )
    }

    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8)) // MAIL FROM
    await transport.yieldIncoming(Array("550 5.1.1 User unknown\r\n".utf8)) // RCPT TO rejected

    await #expect(throws: SmtpCommandError.self) {
        _ = try await sendTask.value
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session sendMail sender rejection")
func asyncSmtpSessionSendMailSenderRejected() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello!\r\n".utf8)
    let sendTask = Task {
        try await session.sendMail(
            from: "blocked@example.com",
            to: ["recipient@example.com"],
            data: messageData
        )
    }

    await transport.yieldIncoming(Array("550 5.1.8 Sender address rejected\r\n".utf8))

    do {
        _ = try await sendTask.value
        Issue.record("Expected SmtpCommandError")
    } catch let error as SmtpCommandError {
        #expect(error.errorCode == .senderNotAccepted)
        #expect(error.mailboxAddress == "blocked@example.com")
    }
}

// MARK: - Pipelining & Chunking

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session sendMailPipelined")
func asyncSmtpSessionSendMailPipelined() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com\r\n".utf8))
    await transport.yieldIncoming(Array("250 PIPELINING\r\n".utf8))
    _ = try await ehloTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello!\r\n".utf8)
    let sendTask = Task {
        try await session.sendMailPipelined(
            from: "sender@example.com",
            to: ["r1@example.com", "r2@example.com"],
            data: messageData
        )
    }

    // Server responds to pipelined commands
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8)) // MAIL FROM
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8)) // RCPT TO 1
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8)) // RCPT TO 2
    await transport.yieldIncoming(Array("354 Go ahead\r\n".utf8)) // DATA
    await transport.yieldIncoming(Array("250 2.0.0 Ok: queued\r\n".utf8))

    let response = try await sendTask.value
    #expect(response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session BDAT chunked transfer")
func asyncSmtpSessionBdat() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com\r\n".utf8))
    await transport.yieldIncoming(Array("250 CHUNKING\r\n".utf8))
    _ = try await ehloTask.value

    let mailTask = Task { try await session.mailFrom("sender@example.com") }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    _ = try await mailTask.value

    let rcptTask = Task { try await session.rcptTo("recipient@example.com") }
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8))
    _ = try await rcptTask.value

    let chunk = Array("Hello chunk".utf8)
    let bdatTask = Task { try await session.sendBdat(chunk, last: true) }
    await transport.yieldIncoming(Array("250 2.0.0 Message accepted\r\n".utf8))
    let response = try await bdatTask.value

    #expect(response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session sendMailChunked")
func asyncSmtpSessionSendMailChunked() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    // Large message that will be split into chunks
    let messageData = Array(repeating: UInt8(65), count: 100) // 100 bytes

    let sendTask = Task {
        try await session.sendMailChunked(
            from: "sender@example.com",
            to: ["recipient@example.com"],
            data: messageData,
            chunkSize: 30
        )
    }

    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8)) // MAIL FROM
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8)) // RCPT TO
    await transport.yieldIncoming(Array("250 Ok\r\n".utf8)) // BDAT chunk 1
    await transport.yieldIncoming(Array("250 Ok\r\n".utf8)) // BDAT chunk 2
    await transport.yieldIncoming(Array("250 Ok\r\n".utf8)) // BDAT chunk 3
    await transport.yieldIncoming(Array("250 2.0.0 Ok: queued\r\n".utf8)) // BDAT LAST

    let response = try await sendTask.value
    #expect(response.code == 250)
}

// MARK: - NOOP, RSET, VRFY, EXPN, HELP

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session NOOP")
func asyncSmtpSessionNoop() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let noopTask = Task { try await session.noop() }
    await transport.yieldIncoming(Array("250 2.0.0 Ok\r\n".utf8))
    let response = try await noopTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session RSET")
func asyncSmtpSessionRset() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let rsetTask = Task { try await session.rset() }
    await transport.yieldIncoming(Array("250 2.0.0 Ok\r\n".utf8))
    let response = try await rsetTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session VRFY")
func asyncSmtpSessionVrfy() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let vrfyTask = Task { try await session.vrfyResult("postmaster") }
    await transport.yieldIncoming(Array("250 2.1.5 postmaster@example.com\r\n".utf8))
    let result = try await vrfyTask.value

    #expect(result.response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session EXPN")
func asyncSmtpSessionExpn() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let expnTask = Task { try await session.expnResult("staff") }
    await transport.yieldIncoming(Array("250-alice@example.com\r\n".utf8))
    await transport.yieldIncoming(Array("250 bob@example.com\r\n".utf8))
    let result = try await expnTask.value

    #expect(result.response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session HELP")
func asyncSmtpSessionHelp() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let helpTask = Task { try await session.helpResult() }
    await transport.yieldIncoming(Array("214-Commands supported:\r\n".utf8))
    await transport.yieldIncoming(Array("214 HELO EHLO MAIL RCPT DATA QUIT\r\n".utf8))
    let result = try await helpTask.value

    #expect(result.response.code == 214)
}

// MARK: - ETRN

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session ETRN")
func asyncSmtpSessionEtrn() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let etrnTask = Task { try await session.etrn("@example.com") }
    await transport.yieldIncoming(Array("250 2.0.0 Queuing started\r\n".utf8))
    let response = try await etrnTask.value

    #expect(response?.code == 250)
}

// MARK: - MAIL FROM/RCPT TO with parameters

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session MAIL FROM with SIZE parameter")
func asyncSmtpSessionMailFromWithSize() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let params = SmtpMailFromParameters(body: .sevenBit, size: 1024)
    let mailTask = Task { try await session.mailFrom("sender@example.com", parameters: params) }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    let response = try await mailTask.value

    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session RCPT TO with NOTIFY parameter")
func asyncSmtpSessionRcptToWithNotify() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let mailTask = Task { try await session.mailFrom("sender@example.com") }
    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    _ = try await mailTask.value

    let params = SmtpRcptToParameters(notify: [.success, .failure])
    let rcptTask = Task { try await session.rcptTo("recipient@example.com", parameters: params) }
    await transport.yieldIncoming(Array("250 2.1.5 Ok\r\n".utf8))
    let response = try await rcptTask.value

    #expect(response?.code == 250)
}

// MARK: - Split Responses

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session handles split responses")
func asyncSmtpSessionSplitResponses() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example".utf8))
    await transport.yieldIncoming(Array(".com ESMTP ready\r\n".utf8))
    let response = try await connectTask.value

    #expect(response?.code == 220)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session handles multiline EHLO split across packets")
func asyncSmtpSessionEhloSplit() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.examp".utf8))
    await transport.yieldIncoming(Array("le.com Hello\r\n250-SIZE ".utf8))
    await transport.yieldIncoming(Array("1000000\r\n".utf8))
    await transport.yieldIncoming(Array("250 8BITMIME\r\n".utf8))
    let caps = try await ehloTask.value

    #expect(caps?.supports("8BITMIME") == true)
    #expect(caps?.value(for: "SIZE") == "1000000")
}

// MARK: - Capabilities Access

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session capabilities accessor")
func asyncSmtpSessionCapabilitiesAccessor() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    // Before EHLO, capabilities should be nil
    let capsBefore = await session.capabilities()
    #expect(capsBefore == nil)

    let ehloTask = Task { try await session.ehlo(domain: "client.example.com") }
    await transport.yieldIncoming(Array("250-mail.example.com Hello\r\n".utf8))
    await transport.yieldIncoming(Array("250 PIPELINING\r\n".utf8))
    _ = try await ehloTask.value

    let capsAfter = await session.capabilities()
    #expect(capsAfter?.supports("PIPELINING") == true)
}

// MARK: - Error Code Verification

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session error includes enhanced status code")
func asyncSmtpSessionEnhancedStatusCode() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 mail.example.com ESMTP ready\r\n".utf8))
    _ = try await connectTask.value

    let messageData = Array("Subject: Test\r\n\r\nHello!\r\n".utf8)
    let sendTask = Task {
        try await session.sendMail(
            from: "sender@example.com",
            to: ["unknown@example.com"],
            data: messageData
        )
    }

    await transport.yieldIncoming(Array("250 2.1.0 Ok\r\n".utf8))
    await transport.yieldIncoming(Array("550 5.1.1 <unknown@example.com>: Recipient rejected\r\n".utf8))

    do {
        _ = try await sendTask.value
        Issue.record("Expected SmtpCommandError")
    } catch let error as SmtpCommandError {
        #expect(error.statusCode == .mailboxUnavailable)
        #expect(error.enhancedStatusCode?.klass == 5)
        #expect(error.enhancedStatusCode?.subject == 1)
        #expect(error.enhancedStatusCode?.detail == 1)
    }
}
