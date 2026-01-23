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
