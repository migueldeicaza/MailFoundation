# Working with SMTP

Send email messages with delivery notifications and advanced features.

## Overview

SMTP (Simple Mail Transfer Protocol) is used for sending email. MailFoundation provides a robust SMTP implementation with support for authentication, TLS, pipelining, chunked transfer, and delivery status notifications.

## Connecting to an SMTP Server

### Using SmtpTransport (Recommended)

The ``SmtpTransport`` class provides the simplest API for sending messages:

```swift
import MailFoundation
import MimeFoundation

// Create transport with STARTTLS (port 587)
let transport = try SmtpTransport.make(
    host: "smtp.example.com",
    port: 587,
    useTls: false  // Will upgrade via STARTTLS
)

try transport.connect()
try transport.authenticate(username: "user@example.com", password: "password")

// Send a message
try transport.send(message)

try transport.disconnect()
```

### Implicit TLS (Port 465)

For servers that require TLS from the start:

```swift
let transport = try SmtpTransport.make(
    host: "smtp.example.com",
    port: 465,
    useTls: true  // Implicit TLS
)
```

### Using SmtpSession (Lower Level)

For more control over the SMTP conversation:

```swift
let socketTransport = try TransportFactory.make(host: "smtp.example.com", port: 587)
let session = SmtpSession(transport: socketTransport)

try session.connect()
try session.ehlo(domain: "client.example.com")
try session.startTls()
try session.ehlo(domain: "client.example.com")  // Re-send after TLS
try session.authenticate(username: "user", password: "pass")

// Send using low-level commands
try session.mail(from: "sender@example.com")
try session.rcpt(to: "recipient@example.com")
try session.data(messageData)

try session.quit()
```

## Sending Messages

### Basic Message Sending

```swift
import MimeFoundation

// Create the message
let message = MimeMessage()
message.from = [MailboxAddress(name: "Alice", address: "alice@example.com")]
message.to = [MailboxAddress(name: "Bob", address: "bob@example.com")]
message.subject = "Hello!"
message.body = TextPart(text: "This is the message body.")

// Send it
try transport.send(message)
```

### Message with HTML and Attachments

```swift
let message = MimeMessage()
message.from = [MailboxAddress(name: "Alice", address: "alice@example.com")]
message.to = [MailboxAddress(name: "Bob", address: "bob@example.com")]
message.subject = "Report Attached"

// Create multipart body
let multipart = Multipart(subtype: "mixed")

// Add HTML alternative
let alternatives = Multipart(subtype: "alternative")
alternatives.add(TextPart(text: "Plain text version"))
alternatives.add(TextPart(text: "<html><body><h1>HTML Version</h1></body></html>", subtype: "html"))
multipart.add(alternatives)

// Add attachment
let attachment = MimePart()
attachment.content = Data(contentsOf: fileURL)
attachment.contentType = ContentType(mediaType: "application", mediaSubtype: "pdf")
attachment.contentDisposition = ContentDisposition(disposition: "attachment", fileName: "report.pdf")
multipart.add(attachment)

message.body = multipart

try transport.send(message)
```

### Multiple Recipients

```swift
message.to = [
    MailboxAddress(name: "Bob", address: "bob@example.com"),
    MailboxAddress(name: "Carol", address: "carol@example.com")
]
message.cc = [
    MailboxAddress(name: "Dave", address: "dave@example.com")
]
message.bcc = [
    MailboxAddress(name: "Eve", address: "eve@example.com")  // Hidden from other recipients
]
```

## Delivery Status Notifications (DSN)

Request delivery receipts:

```swift
// Request notification on success and failure
let options = SmtpDeliveryOptions(
    notify: [.success, .failure],
    returnType: .headers  // Return headers only, not full message
)

try transport.send(message, options: options)
```

### DSN Options

| Option | Description |
|--------|-------------|
| `.never` | Never send notifications |
| `.success` | Notify on successful delivery |
| `.failure` | Notify on delivery failure |
| `.delay` | Notify if delivery is delayed |

### Return Types

| Type | Description |
|------|-------------|
| `.full` | Return the full original message |
| `.headers` | Return headers only (smaller) |

## Message Sent Handler

Track sent messages with a callback:

```swift
transport.messageSent = { event in
    print("Message sent!")
    print("Response: \(event.response)")

    // Access the sent message
    let message = event.message
    print("Subject: \(message.subject ?? "No subject")")
}

try transport.send(message)
```

## Server Capabilities

Check what the server supports:

```swift
let session = SmtpSession(transport: socketTransport)
try session.connect()
try session.ehlo(domain: "client.example.com")

let caps = session.capabilities

if caps.contains(.pipelining) {
    print("Server supports pipelining")
}
if caps.contains(.chunking) {
    print("Server supports BDAT chunking")
}
if caps.contains(.size) {
    print("Max message size: \(session.maxSize ?? 0) bytes")
}
if caps.contains(.eightBitMime) {
    print("Server supports 8-bit MIME")
}
if caps.contains(.smtpUtf8) {
    print("Server supports UTF-8 addresses")
}
if caps.contains(.dsn) {
    print("Server supports delivery notifications")
}
```

## Pipelining

When supported, commands are sent in batches for efficiency:

```swift
// SmtpTransport automatically uses pipelining when available
// For manual control with SmtpSession:

if session.capabilities.contains(.pipelining) {
    // Commands are automatically pipelined
    try session.sendPipelined(messages: [message1, message2, message3])
}
```

## Chunked Transfer (BDAT)

For large messages, use BDAT instead of DATA:

```swift
// SmtpTransport automatically uses BDAT when available
// This is more efficient for large messages as it doesn't require
// dot-stuffing and allows progress tracking
```

## International Email Addresses

Support for non-ASCII addresses (SMTPUTF8):

```swift
let message = MimeMessage()
message.from = [MailboxAddress(name: "Mller", address: "mller@example.com")]
message.to = [MailboxAddress(name: "", address: "@example.com")]  // Japanese

// The transport automatically uses SMTPUTF8 when needed
try transport.send(message)
```

## Error Handling

### SMTP Response Codes

```swift
do {
    try transport.send(message)
} catch let error as SmtpCommandError {
    switch error {
    case .rejected(let code, let message):
        print("Rejected with code \(code): \(message)")

        // Check specific error codes
        switch code {
        case 550:
            print("Mailbox not found")
        case 552:
            print("Message too large")
        case 554:
            print("Transaction failed")
        default:
            print("SMTP error \(code)")
        }

    case .authenticationFailed(let message):
        print("Auth failed: \(message)")

    case .notConnected:
        print("Not connected to server")
    }
}
```

### Enhanced Status Codes

SMTP servers may provide detailed status codes:

```swift
if case .rejected(_, let message) = error,
   let enhanced = SmtpEnhancedStatusCode.parse(message) {
    print("Class: \(enhanced.class)")      // e.g., 5 (permanent failure)
    print("Subject: \(enhanced.subject)")  // e.g., 1 (address)
    print("Detail: \(enhanced.detail)")    // e.g., 1 (bad destination)
}
```

## VRFY and EXPN Commands

Verify addresses (if server allows):

```swift
// Verify a single address
let result = try session.verify(address: "user@example.com")
print("Address valid: \(result.isSuccess)")

// Expand a mailing list
let members = try session.expand(address: "list@example.com")
for member in members {
    print("Member: \(member.address)")
}
```

> Note: Many servers disable VRFY/EXPN for security reasons.

## Protocol Logging

Debug SMTP conversations:

```swift
let logger = ConsoleProtocolLogger()
let transport = try SmtpTransport.make(
    host: "smtp.example.com",
    port: 587,
    protocolLogger: logger
)

// All commands and responses are logged
// Credentials are automatically masked
```

Example output:
```
C: EHLO client.example.com
S: 250-smtp.example.com Hello
S: 250-PIPELINING
S: 250-SIZE 35882577
S: 250-AUTH PLAIN LOGIN
S: 250 8BITMIME
C: AUTH PLAIN ********
S: 235 2.7.0 Authentication successful
```

## Async SMTP

Use async/await for non-blocking operations:

```swift
let transport = try await AsyncSmtpTransport.make(
    host: "smtp.example.com",
    port: 587
)

try await transport.connect()
try await transport.authenticate(username: "user", password: "pass")
try await transport.send(message)
try await transport.disconnect()
```

## Best Practices

1. **Always use authentication** - Open relays are blocked by most servers
2. **Use TLS** - Either STARTTLS (port 587) or implicit TLS (port 465)
3. **Handle bounces** - Set up DSN or monitor the return address
4. **Respect rate limits** - Don't send too many messages too quickly
5. **Validate addresses** - Check format before sending
6. **Set proper headers** - Include Message-ID, Date, and proper From/Reply-To
7. **Handle failures gracefully** - Retry transient errors, log permanent failures
