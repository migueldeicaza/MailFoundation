# ``MailFoundation``

A cross-platform Swift library for IMAP, SMTP, and POP3 mail protocols.

@Metadata {
    @DisplayName("MailFoundation")
    @PageImage(purpose: icon, source: "mail-icon", alt: "A mail envelope icon")
}

## Overview

MailFoundation is a Swift port of the popular [MailKit](https://github.com/jstedfast/MailKit) C# library, providing robust, standards-compliant implementations of the major email protocols:

- **IMAP4rev1** - Full mailbox access with 50+ protocol extensions
- **SMTP** - Message sending with DSN, pipelining, and chunked transfer
- **POP3** - Simple message retrieval with APOP and SASL authentication

The library is designed for both synchronous and asynchronous usage, with native Swift concurrency support using async/await and actors.

### Key Features

- **Complete Protocol Support** - Implements core protocols plus modern extensions
- **Flexible Authentication** - PLAIN, LOGIN, CRAM-MD5, XOAUTH2, and more
- **TLS/SSL Security** - STARTTLS and implicit TLS with certificate validation
- **Proxy Support** - HTTP CONNECT, SOCKS4, SOCKS4a, and SOCKS5 proxies
- **Modern Swift APIs** - Both sync and async APIs with Sendable types
- **Protocol Logging** - Debug protocol conversations with secret masking
- **MimeFoundation Integration** - Works seamlessly with MimeFoundation for message handling

### Architecture

MailFoundation follows a layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│         (SearchQuery, MessageSummary, Threading)            │
├─────────────────────────────────────────────────────────────┤
│                    Service Layer                             │
│    (ImapMailStore, SmtpTransport, Pop3MailStore)            │
├─────────────────────────────────────────────────────────────┤
│                    Session Layer                             │
│  (ImapSession, SmtpSession, Pop3Session + Async variants)   │
├─────────────────────────────────────────────────────────────┤
│                    Protocol Layer                            │
│    (ImapClient, SmtpClient, Pop3Client + Async variants)    │
├─────────────────────────────────────────────────────────────┤
│                    Transport Layer                           │
│  (Transport, AsyncTransport, TLS, Proxy, ConnectionPool)    │
└─────────────────────────────────────────────────────────────┘
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Features>
- <doc:Authentication>

### Protocols

- <doc:WorkingWithIMAP>
- <doc:WorkingWithSMTP>
- <doc:WorkingWithPOP3>

### Advanced Topics

- <doc:TransportAndProxy>
- <doc:SearchAndThreading>
- <doc:AsyncPatterns>

### Mail Stores and Transports

- ``ImapMailStore``
- ``AsyncImapMailStore``
- ``Pop3MailStore``
- ``AsyncPop3MailStore``
- ``SmtpTransport``
- ``AsyncSmtpTransport``

### Sessions

- ``ImapSession``
- ``AsyncImapSession``
- ``SmtpSession``
- ``AsyncSmtpSession``
- ``Pop3Session``
- ``AsyncPop3Session``

### Message Types

- ``MessageSummary``
- ``Envelope``
- ``MessageFlags``
- ``ImapBodyStructure``

### Identifiers

- ``UniqueId``
- ``UniqueIdRange``
- ``UniqueIdSet``
- ``SequenceSet``

### Search and Threading

- ``SearchQuery``
- ``MessageThreader``
- ``MessageSorter``
- ``OrderBy``

### Transport

- ``TlsConfiguration``
- ``ProxySettings``
- ``ConnectionPool``
