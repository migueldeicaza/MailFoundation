import Testing
@testable import MailFoundation
import SwiftMimeKit

@Test("SMTP transport send chunked")
func smtpTransportSendChunked() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250-CHUNKING\r\n250 SIZE 120\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 3)
    _ = try smtp.connect()
    _ = try smtp.ehlo(domain: "localhost")

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"
    message.body = TextPart("Hello")

    let response = try smtp.sendChunked(message, chunkSize: 1024)
    #expect(response.isSuccess)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains(where: { $0.hasPrefix("BDAT ") }))
    #expect(!sent.contains(where: { $0 == "DATA\r\n" }))
    #expect(sent.contains(where: { $0.hasPrefix("MAIL FROM:<alice@example.com>") && $0.contains("SIZE=") }))
}

@Test("SMTP transport requires connection")
func smtpTransportRequiresConnection() throws {
    let transport = TestTransport(incoming: [])
    let smtp = SmtpTransport(transport: transport, maxReads: 1)

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    #expect(throws: MailTransportError.notConnected) {
        _ = try smtp.send(message)
    }
}

@Test("SMTP transport requires SMTPUTF8 for international")
func smtpTransportRequiresSmtpUtf8() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 2)
    _ = try smtp.connect()
    _ = try smtp.ehlo(domain: "localhost")

    var options = MailTransportFormatOptions.default
    options.international = true

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    #expect(throws: MailTransportError.internationalNotSupported) {
        _ = try smtp.send(message, options: options)
    }
}

@Test("SMTP transport uses SMTPUTF8 when requested")
func smtpTransportUsesSmtpUtf8() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250-SMTPUTF8\r\n250 SIZE 12\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("354 End data\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 3)
    _ = try smtp.connect()
    _ = try smtp.ehlo(domain: "localhost")

    var options = MailTransportFormatOptions.default
    options.international = true

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    let response = try smtp.send(message, options: options)
    #expect(response.isSuccess)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains(where: { $0.hasPrefix("MAIL FROM:<alice@example.com>") && $0.contains("SMTPUTF8") }))
}

@Test("SMTP transport message sent handler")
func smtpTransportMessageSentHandler() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("354 End data\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 3)
    _ = try smtp.connect()
    _ = try smtp.ehlo(domain: "localhost")

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    let box = MessageSentBox()
    smtp.addMessageSentHandler { event in
        box.value = event
    }

    let response = try smtp.send(message)
    #expect(response.isSuccess)
    #expect(box.value != nil)
    #expect(box.value?.message === message)
    #expect(box.value?.response.contains("OK") == true)
}

@Test("SMTP transport send pipelined")
func smtpTransportSendPipelined() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250-PIPELINING\r\n250 SIZE 120\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("354 End data\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 3)
    _ = try smtp.connect()
    _ = try smtp.ehlo(domain: "localhost")

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"
    message.body = TextPart("Hello")

    let response = try smtp.sendPipelined(message)
    #expect(response.isSuccess)

    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains(where: { $0.hasPrefix("MAIL FROM:<alice@example.com>") }))
}

@Test("SMTP transport VRFY/EXPN/HELP helpers")
func smtpTransportExtendedCommands() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("252 <alice@example.com>\r\n".utf8),
        Array("250-<bob@example.com>\r\n250 <carol@example.com>\r\n".utf8),
        Array("214-Commands:\r\n214 VRFY EXPN HELP\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 3)
    _ = try smtp.connect()

    let vrfy = try smtp.vrfyResult("alice")
    #expect(vrfy.mailboxes.count == 1)
    #expect(vrfy.mailboxes.first?.address == "alice@example.com")

    let expn = try smtp.expnResult("list")
    #expect(expn.mailboxes.count == 2)

    let help = try smtp.helpResult()
    #expect(help.text.contains("VRFY") == true)
}

@Test("SMTP transport VRFY error response")
func smtpTransportVrfyErrorResponse() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("550 No such user\r\n".utf8)
    ])
    let smtp = SmtpTransport(transport: transport, maxReads: 2)
    _ = try smtp.connect()

    #expect(throws: SessionError.smtpError(code: 550, message: "No such user")) {
        _ = try smtp.vrfy("missing")
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport send chunked")
func asyncSmtpTransportSendChunked() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await smtp.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250-CHUNKING\r\n250 SIZE 120\r\n".utf8))
    _ = try await ehloTask.value

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"
    message.body = TextPart("Hello")

    let sendTask = Task { try await smtp.sendChunked(message, chunkSize: 1024) }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await sendTask.value
    #expect(response.isSuccess)

    let sent = await transport.sentSnapshot()
    let sentText = sent.map { String(decoding: $0, as: UTF8.self) }
    #expect(sentText.contains(where: { $0.hasPrefix("BDAT ") }))
    #expect(sentText.contains(where: { $0.hasPrefix("MAIL FROM:<alice@example.com>") && $0.contains("SIZE=") }))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport requires connection")
func asyncSmtpTransportRequiresConnection() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    do {
        _ = try await smtp.send(message)
        #expect(Bool(false))
    } catch {
        #expect(error as? MailTransportError == .notConnected)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport VRFY/EXPN/HELP helpers")
func asyncSmtpTransportExtendedCommands() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let vrfyTask = Task { try await smtp.vrfyResult("alice") }
    await transport.yieldIncoming(Array("252 <alice@example.com>\r\n".utf8))
    let vrfy = try await vrfyTask.value
    #expect(vrfy.mailboxes.count == 1)
    #expect(vrfy.mailboxes.first?.address == "alice@example.com")

    let expnTask = Task { try await smtp.expnResult("list") }
    await transport.yieldIncoming(Array("250-<bob@example.com>\r\n250 <carol@example.com>\r\n".utf8))
    let expn = try await expnTask.value
    #expect(expn.mailboxes.count == 2)

    let helpTask = Task { try await smtp.helpResult() }
    await transport.yieldIncoming(Array("214-Commands:\r\n214 VRFY EXPN HELP\r\n".utf8))
    let help = try await helpTask.value
    #expect(help.text.contains("VRFY") == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport VRFY error response")
func asyncSmtpTransportVrfyErrorResponse() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let vrfyTask = Task { try await smtp.vrfy("missing") }
    await transport.yieldIncoming(Array("550 No such user\r\n".utf8))
    do {
        _ = try await vrfyTask.value
        #expect(Bool(false))
    } catch {
        #expect(error as? SessionError == .smtpError(code: 550, message: "No such user"))
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport requires SMTPUTF8 for international")
func asyncSmtpTransportRequiresSmtpUtf8() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await smtp.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8))
    _ = try await ehloTask.value

    var options = MailTransportFormatOptions.default
    options.international = true

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    do {
        _ = try await smtp.send(message, options: options)
        #expect(Bool(false))
    } catch {
        #expect(error as? MailTransportError == .internationalNotSupported)
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport message sent handler")
func asyncSmtpTransportMessageSentHandler() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await smtp.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8))
    _ = try await ehloTask.value

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"

    let collector = MessageSentCollector()
    await smtp.addMessageSentHandler { event in
        await collector.store(event)
    }

    let sendTask = Task { try await smtp.send(message) }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("354 End data\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await sendTask.value
    #expect(response.isSuccess)

    let captured = await collector.snapshot()
    #expect(captured != nil)
    #expect(captured?.message === message)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP transport send pipelined")
func asyncSmtpTransportSendPipelined() async throws {
    let transport = AsyncStreamTransport()
    let smtp = AsyncSmtpTransport(transport: transport)

    let connectTask = Task { try await smtp.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let ehloTask = Task { try await smtp.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250-PIPELINING\r\n250 SIZE 120\r\n".utf8))
    _ = try await ehloTask.value

    let message = MimeMessage()
    message.headers[.from] = "Alice <alice@example.com>"
    message.headers[.to] = "Bob <bob@example.com>"
    message.body = TextPart("Hello")

    let sendTask = Task { try await smtp.sendPipelined(message) }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("354 End data\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await sendTask.value
    #expect(response.isSuccess)
}

@available(macOS 10.15, iOS 13.0, *)
private actor MessageSentCollector {
    private var event: MessageSentEvent?

    func store(_ event: MessageSentEvent) {
        self.event = event
    }

    func snapshot() -> MessageSentEvent? {
        event
    }
}

private final class MessageSentBox: @unchecked Sendable {
    var value: MessageSentEvent?
}
