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
