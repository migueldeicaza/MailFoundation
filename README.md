# MailFoundation

<p align="center">
  <img src="mailfoundation.webp" alt="MailFoundation Banner" style="max-width: 100%; height: auto;">
</p>

MailFoundation is a Swift package that provides IMAP, POP3, and SMTP client stacks plus
mail metadata utilities. It is designed to pair with [MimeFoundation](https://github.com/migueldeicaza/MimeFoundation) 
for MIME parsing and message construction while providing a focused, protocol-level 
foundation for mail applications and services.

## Origin and goal

This project is a port of the .NET Foundation mail stack originally created by
Jeffrey Stedfast [MailKit](https://github.com/jstedfast/MailKit)/[MimeKit](https://github.com/jstedfast/MimeKit). 
The goal is to bring those capabilities and API ergonomics to Swift developers, with modern async/await 
support and a Swift-native type system.

## Features

- IMAP, POP3, and SMTP client stacks with sync and async APIs.
- Async mail stores and transports (`AsyncImapMailStore`, `AsyncPop3MailStore`, `AsyncSmtpTransport`).
- SASL authentication including SCRAM, NTLM, GSSAPI, CRAM-MD5, and XOAUTH2.
- STARTTLS and TLS support via Network framework, POSIX sockets, or OpenSSL.
- Proxy support (SOCKS4/5, HTTP CONNECT).
- Search and threading helpers (`SearchQuery`, `MessageThreader`, threading references).
- Retry policies, timeouts, and connection pooling.
- Protocol logging and authentication secret redaction.

## Requirements

- Swift 6.2+
- macOS 10.15+ (visionOS 1.0+ per Package.swift)

## Installation (Swift Package Manager)

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/MailFoundation", branch: "main")
]
```

Then add `MailFoundation` to your target dependencies:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            "MailFoundation"
        ]
    )
]
```

## Usage

### Async IMAP example

```swift
import MailFoundation

let store = try AsyncImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    backend: .network
)
try await store.connect()
try await store.authenticate(user: "user@example.com", password: "secret")

let inbox = try await store.openInbox(access: .readOnly)
let results = try await store.search(.all)
print("Found \(results.ids.count) messages")

await store.disconnect()
```

### Async SMTP example

```swift
import MailFoundation
import MimeFoundation

let transport = try AsyncSmtpTransport.make(
    host: "smtp.example.com",
    port: 587,
    backend: .network
)
try await transport.connect()
_ = try await transport.ehlo(domain: "client.example.com")

try await transport.authenticate(SmtpPlainAuthentication(
    username: "user@example.com",
    password: "secret"
))

let message = MimeMessage()
message.from = [MailboxAddress("sender@example.com")]
message.to = [MailboxAddress("recipient@example.com")]
message.subject = "Hello"
message.textBody = "Hello, World!"

try await transport.send(message)
await transport.disconnect()
```

## Documentation

DocC documentation lives under `Sources/MailFoundation/MailFoundation.docc`.
You can generate it locally with:

```bash
swift package generate-documentation \
  --target MailFoundation \
  --output-path ./docs \
  --transform-for-static-hosting
```
