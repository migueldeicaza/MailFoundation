# Features and Capabilities

A comprehensive overview of MailFoundation's protocol support, extensions, and capabilities.

## Overview

MailFoundation is a full-featured mail library implementing IMAP4rev1, SMTP, and POP3 protocols with extensive extension support. This page provides a complete reference of supported features.   MailFoundation is a Swift port of Jeff Stedfast's popular [MailKit](https://github.com/jstedfast/MailKit) C# library. 

## Protocol Support Summary

| Protocol | Version | Extensions |
|----------|---------|------------|
| IMAP | IMAP4rev1 (RFC 3501) | 50+ extensions |
| SMTP | ESMTP (RFC 5321) | 15+ extensions |
| POP3 | POP3 (RFC 1939) | 10+ extensions |

## IMAP Extensions

MailFoundation supports the following IMAP protocol extensions:

### Core Extensions

| Extension | RFC | Description |
|-----------|-----|-------------|
| **LITERAL+** | RFC 7888 | Non-synchronizing literals |
| **SASL-IR** | RFC 4959 | Initial client response in AUTH |
| **LOGIN-REFERRALS** | RFC 2221 | Server referrals for login |
| **MAILBOX-REFERRALS** | RFC 2193 | Server referrals for mailboxes |
| **NAMESPACE** | RFC 2342 | Mailbox namespace discovery |
| **ID** | RFC 2971 | Client/server identification |
| **ENABLE** | RFC 5161 | Enable optional capabilities |
| **UNSELECT** | RFC 3691 | Unselect without expunge |

### Mailbox Management

| Extension | RFC | Description |
|-----------|-----|-------------|
| **CREATE-SPECIAL-USE** | RFC 6154 | Create special-use folders |
| **SPECIAL-USE** | RFC 6154 | Identify special folders |
| **XLIST** | - | Gmail folder extensions |
| **LIST-EXTENDED** | RFC 5258 | Extended LIST command |
| **LIST-STATUS** | RFC 5819 | STATUS in LIST response |
| **CHILDREN** | RFC 3348 | HasChildren/HasNoChildren |
| **METADATA** | RFC 5464 | Server/mailbox metadata |
| **METADATA-SERVER** | RFC 5464 | Server-level metadata |

### Message Access

| Extension | RFC | Description |
|-----------|-----|-------------|
| **BINARY** | RFC 3516 | Binary content transfer |
| **CATENATE** | RFC 4469 | Server-side message composition |
| **CONVERT** | RFC 5259 | Content conversion |
| **PREVIEW** | RFC 8970 | Message preview snippets |
| **SNIPPET** | - | Text snippets (draft) |

### Search and Sort

| Extension | RFC | Description |
|-----------|-----|-------------|
| **SORT** | RFC 5256 | Server-side sorting |
| **SORT=DISPLAY** | RFC 5957 | Sort by display name |
| **THREAD** | RFC 5256 | Server-side threading |
| **THREAD=ORDEREDSUBJECT** | RFC 5256 | Subject-based threading |
| **THREAD=REFERENCES** | RFC 5256 | References-based threading |
| **ESEARCH** | RFC 4731 | Extended search results |
| **SEARCHRES** | RFC 5182 | Search result references |
| **SEARCH=FUZZY** | RFC 6203 | Fuzzy search |
| **CONTEXT=SEARCH** | RFC 5267 | Search context |
| **CONTEXT=SORT** | RFC 5267 | Sort context |
| **FILTERS** | RFC 5466 | Named search filters |

### Synchronization

| Extension | RFC | Description |
|-----------|-----|-------------|
| **CONDSTORE** | RFC 7162 | Conditional STORE |
| **QRESYNC** | RFC 7162 | Quick resync |
| **UIDPLUS** | RFC 4315 | UID EXPUNGE and responses |

### Real-time Updates

| Extension | RFC | Description |
|-----------|-----|-------------|
| **IDLE** | RFC 2177 | Push notifications |
| **NOTIFY** | RFC 5465 | Advanced notifications |

### Access Control

| Extension | RFC | Description |
|-----------|-----|-------------|
| **ACL** | RFC 4314 | Access control lists |
| **RIGHTS=** | RFC 4314 | Rights capability |
| **LISTRIGHTS** | RFC 4314 | List available rights |

### Quotas

| Extension | RFC | Description |
|-----------|-----|-------------|
| **QUOTA** | RFC 9208 | Mailbox quotas |
| **QUOTA=RES-STORAGE** | RFC 9208 | Storage quota |
| **QUOTA=RES-MESSAGE** | RFC 9208 | Message count quota |

### Annotations

| Extension | RFC | Description |
|-----------|-----|-------------|
| **ANNOTATE** | - | Message annotations (draft) |
| **ANNOTATEMORE** | - | Extended annotations |

### Message Operations

| Extension | RFC | Description |
|-----------|-----|-------------|
| **MOVE** | RFC 6851 | Native MOVE command |
| **REPLACE** | RFC 8508 | Replace message |
| **MULTIAPPEND** | RFC 3502 | Append multiple messages |
| **APPENDLIMIT** | RFC 7889 | Append size limit |
| **OBJECTID** | RFC 8474 | Stable object identifiers |
| **SAVEDATE** | RFC 8514 | Message save date |

### Internationalization

| Extension | RFC | Description |
|-----------|-----|-------------|
| **UTF8=ACCEPT** | RFC 6855 | UTF-8 support |
| **UTF8=ONLY** | RFC 6855 | UTF-8 required |
| **I18NLEVEL=1** | RFC 5255 | Internationalization |
| **I18NLEVEL=2** | RFC 5255 | Extended i18n |
| **LANGUAGE** | RFC 5255 | Language negotiation |

### Compression

| Extension | RFC | Description |
|-----------|-----|-------------|
| **COMPRESS=DEFLATE** | RFC 4978 | DEFLATE compression |

### Status

| Extension | RFC | Description |
|-----------|-----|-------------|
| **STATUS=SIZE** | RFC 8438 | Mailbox size in STATUS |

## SMTP Extensions

### Core Extensions

| Extension | RFC | Description |
|-----------|-----|-------------|
| **SIZE** | RFC 1870 | Message size declaration |
| **8BITMIME** | RFC 6152 | 8-bit MIME transport |
| **PIPELINING** | RFC 2920 | Command pipelining |
| **ENHANCEDSTATUSCODES** | RFC 2034 | Enhanced status codes |
| **CHUNKING** | RFC 3030 | BDAT command |
| **BINARYMIME** | RFC 3030 | Binary MIME |

### Security

| Extension | RFC | Description |
|-----------|-----|-------------|
| **STARTTLS** | RFC 3207 | TLS upgrade |
| **AUTH** | RFC 4954 | SASL authentication |
| **REQUIRETLS** | RFC 8689 | Require TLS |

### Internationalization

| Extension | RFC | Description |
|-----------|-----|-------------|
| **SMTPUTF8** | RFC 6531 | UTF-8 addresses |

### Delivery Notifications

| Extension | RFC | Description |
|-----------|-----|-------------|
| **DSN** | RFC 3461 | Delivery status notifications |

### Other

| Extension | RFC | Description |
|-----------|-----|-------------|
| **VRFY** | RFC 5321 | Verify address |
| **EXPN** | RFC 5321 | Expand mailing list |
| **HELP** | RFC 5321 | Help command |

## POP3 Extensions

| Extension | RFC | Description |
|-----------|-----|-------------|
| **TOP** | RFC 1939 | Fetch message headers |
| **UIDL** | RFC 1939 | Unique ID listing |
| **USER** | RFC 1939 | USER/PASS authentication |
| **APOP** | RFC 1939 | APOP authentication |
| **SASL** | RFC 5034 | SASL authentication |
| **STLS** | RFC 2595 | STARTTLS |
| **CAPA** | RFC 2449 | Capability discovery |
| **PIPELINING** | RFC 2449 | Command pipelining |
| **EXPIRE** | RFC 2449 | Message expiration |
| **LOGIN-DELAY** | RFC 2449 | Login delay |
| **UTF8** | RFC 6856 | UTF-8 support |
| **LANG** | RFC 6856 | Language selection |

## Authentication Mechanisms

MailFoundation supports the following SASL authentication mechanisms:

| Mechanism | Security | Description |
|-----------|----------|-------------|
| **PLAIN** | Low | Base64 credentials (use with TLS) |
| **LOGIN** | Low | Legacy two-step auth |
| **CRAM-MD5** | Medium | Challenge-response with MD5 |
| **XOAUTH2** | High | OAuth2 bearer tokens |
| **OAUTHBEARER** | High | RFC 7628 OAuth |

### OAuth2 Provider Support

- Google (Gmail, Google Workspace)
- Microsoft (Outlook.com, Office 365, Exchange Online)
- Any OAuth2-compliant provider

## Security Features

### TLS/SSL

- TLS 1.2 and TLS 1.3 support
- Implicit TLS (direct connection)
- STARTTLS upgrade
- Certificate validation with customization
- Client certificate authentication
- Configurable cipher suites

### Credential Protection

- Automatic secret masking in protocol logs
- Secure credential handling
- No plaintext password storage

## Transport Features

### Connection Options

- TCP/IP streams (Foundation)
- POSIX sockets with OpenSSL
- Network.framework (Apple platforms)

### Proxy Support

| Proxy Type | Authentication |
|------------|----------------|
| HTTP CONNECT | Optional |
| SOCKS4 | No |
| SOCKS4a | No |
| SOCKS5 | Optional |

### Reliability

- Connection pooling
- Configurable timeouts
- Retry policies with exponential backoff
- Automatic reconnection

## Message Features

### Envelope Metadata

- From, To, CC, BCC, Reply-To addresses
- Subject with encoding support
- Date parsing (RFC 2822, RFC 5322)
- Message-ID, In-Reply-To, References
- List headers (List-Id, List-Unsubscribe, etc.)
- Authentication headers (DKIM, SPF, ARC)

### Body Structure

- MIME multipart parsing
- Content type and encoding detection
- Attachment enumeration
- Nested message support
- Partial fetch support

### Threading

- References-based threading (RFC 5256)
- OrderedSubject threading
- Subject normalization
- Reply detection

### Search

- Fluent query builder API
- All IMAP search criteria
- Query optimization
- Client-side sorting

## Concurrency

### Synchronous API

- Blocking operations
- Simple sequential code
- Thread-safe with proper synchronization

### Asynchronous API

- Full async/await support
- Actor-based session management
- Sendable types for concurrency safety
- Structured concurrency patterns
- Cancellation support

## Platform Support

| Platform | Minimum Version | Notes |
|----------|-----------------|-------|
| macOS | 12.0+ | Full support |
| iOS | 15.0+ | Full support |
| tvOS | 15.0+ | Full support |
| watchOS | 8.0+ | Limited (no background) |
| Linux | Swift 5.9+ | Requires OpenSSL |

## Dependencies

- **MimeFoundation** - MIME message handling
- **OpenSSL** (Linux) - TLS support

## Standards Compliance

MailFoundation strives for strict RFC compliance while handling real-world server quirks:

### Core RFCs

- RFC 3501 - IMAP4rev1
- RFC 5321 - SMTP
- RFC 1939 - POP3
- RFC 5322 - Internet Message Format
- RFC 2045-2049 - MIME

### Security RFCs

- RFC 8314 - Cleartext Considered Obsolete
- RFC 4954 - SMTP AUTH
- RFC 5034 - POP3 SASL
- RFC 7628 - OAUTHBEARER

See the complete list of supported RFCs in the source repository.

## Comparison with MailKit

MailFoundation is a Swift port of the popular [MailKit](https://github.com/jstedfast/MailKit) C# library. Key similarities and differences:

### Similarities

- Same architectural patterns
- Equivalent protocol support
- Similar API design philosophy
- Comprehensive extension support

### Swift Adaptations

- Native async/await instead of Task-based async
- Swift value types where appropriate
- Actor-based concurrency
- Sendable protocol conformance
- Swift error handling patterns
- Integration with MimeFoundation (Swift MIME library)
