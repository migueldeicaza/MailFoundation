# Working with POP3

Retrieve and manage messages with the POP3 protocol.

## Overview

POP3 (Post Office Protocol version 3) is a simple protocol for retrieving email. Unlike IMAP, POP3 treats the mailbox as a single queue of messages without folder support. It's ideal for downloading messages to local storage.

## When to Use POP3

**Use POP3 when:**
- You want to download messages and store them locally
- You don't need folder organization on the server
- You're working with older or simpler mail servers
- You want a straightforward download-and-delete workflow

**Use IMAP instead when:**
- You need folder support
- You want to sync across multiple devices
- You need server-side search
- You want to leave messages on the server

## Connecting to a POP3 Server

### Using Pop3MailStore (Recommended)

```swift
import MailFoundation

// Create store with implicit TLS
let store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true
)

try store.connect()
try store.authenticate(username: "user@example.com", password: "password")

// Work with messages...

try store.disconnect()
```

### Using Pop3Session (Lower Level)

```swift
let transport = try TransportFactory.make(host: "pop.example.com", port: 995)
let session = Pop3Session(transport: transport)

try session.connect()
try session.authenticate(username: "user", password: "pass")

// Execute commands...

try session.quit()
```

## The Inbox Folder

POP3 has only one folder - the inbox:

```swift
let inbox = try store.inbox()
try inbox.open()

print("Total messages: \(inbox.count)")
print("Total size: \(inbox.size) bytes")
```

## Listing Messages

### Get Message List

```swift
// Get list of all messages with sizes
let messages = try inbox.list()

for msg in messages {
    print("Message \(msg.number): \(msg.size) bytes")
}
```

### Get Unique IDs

```swift
// Get unique identifiers (persist across sessions)
let uidls = try inbox.uidl()

for item in uidls {
    print("Message \(item.number): UID = \(item.uid)")
}
```

Unique IDs are stable identifiers that don't change, unlike message numbers which can shift when messages are deleted.

## Retrieving Messages

### Download a Complete Message

```swift
// By message number (1-based)
let message = try inbox.getMessage(at: 1)

print("From: \(message.from.first?.address ?? "unknown")")
print("Subject: \(message.subject ?? "No subject")")
print("Date: \(message.date?.description ?? "unknown")")

// Access the body
if let textBody = message.textBody {
    print("Body: \(textBody)")
}
```

### Download Message Headers Only

Use TOP to fetch just the headers (saves bandwidth):

```swift
// Get headers + first 0 lines of body (headers only)
let headers = try inbox.getMessageHeaders(at: 1)

print("Subject: \(headers.subject ?? "No subject")")
```

### Download Partial Message

```swift
// Get headers + first N lines of body (preview)
let preview = try inbox.getMessageTop(at: 1, lines: 10)
```

### Download as Raw Data

```swift
// Get raw message bytes
let data = try inbox.getMessageData(at: 1)

// Parse later if needed
let message = try MimeMessage(data: data)
```

## Deleting Messages

POP3 deletion is a two-phase process:

```swift
// 1. Mark messages for deletion
try inbox.delete(at: 1)
try inbox.delete(at: 2)

// 2. Commit deletions by closing the session
try store.disconnect()  // Deletions are committed here
```

### Cancel Deletions

If you change your mind before disconnecting:

```swift
// Mark for deletion
try inbox.delete(at: 1)

// Oops, undo all deletions
try session.reset()

// Message 1 is no longer marked for deletion
```

## Authentication Methods

### USER/PASS (Basic)

```swift
try session.authenticate(username: "user", password: "pass")
```

### APOP (Challenge-Response)

If the server supports APOP:

```swift
if session.supportsApop {
    try session.authenticateApop(username: "user", password: "pass")
} else {
    try session.authenticate(username: "user", password: "pass")
}
```

APOP is more secure than USER/PASS as the password is never sent in cleartext.

### SASL Authentication

```swift
// CRAM-MD5
try session.authenticate(username: "user", password: "pass", mechanism: .cramMd5)

// OAuth2
try session.authenticateOAuth2(username: "user", accessToken: token)
```

## Server Capabilities

Check what the server supports:

```swift
let session = Pop3Session(transport: transport)
try session.connect()

let caps = try session.capabilities()

if caps.contains(.top) {
    print("Server supports TOP command")
}
if caps.contains(.uidl) {
    print("Server supports UIDL command")
}
if caps.contains(.sasl) {
    print("Server supports SASL authentication")
}
if caps.contains(.stls) {
    print("Server supports STARTTLS")
}
```

## TLS/SSL

### Implicit TLS (Port 995)

```swift
let store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true
)
```

### STARTTLS (Port 110)

```swift
let store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 110,
    useTls: false
)

try store.connect()
try store.startTls()  // Upgrade to TLS
try store.authenticate(username: "user", password: "pass")
```

## Efficient Message Processing

### Download Strategy

For large mailboxes, process messages efficiently:

```swift
let inbox = try store.inbox()
try inbox.open()

// Get all UIDs first
let uidls = try inbox.uidl()

// Check which messages are new (compare with local database)
let newMessages = uidls.filter { !localDatabase.contains($0.uid) }

// Download only new messages
for item in newMessages {
    let message = try inbox.getMessage(at: item.number)

    // Save locally
    localDatabase.save(message, uid: item.uid)

    // Optionally delete from server
    try inbox.delete(at: item.number)
}

try store.disconnect()
```

### Leave Messages on Server

To keep messages on the server for access from other devices:

```swift
// Just download without deleting
for i in 1...inbox.count {
    let message = try inbox.getMessage(at: i)
    localDatabase.save(message)
    // Don't call delete()
}

try store.disconnect()
```

## Error Handling

```swift
do {
    try inbox.getMessage(at: 999)
} catch let error as Pop3CommandError {
    switch error {
    case .commandFailed(let message):
        print("Command failed: \(message)")
    case .authenticationFailed(let message):
        print("Auth failed: \(message)")
    case .notConnected:
        print("Not connected")
    }
}
```

## Async POP3

```swift
let store = try await AsyncPop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true
)

try await store.connect()
try await store.authenticate(username: "user", password: "pass")

let inbox = try await store.inbox()
try await inbox.open()

let count = inbox.count
print("Messages: \(count)")

for i in 1...count {
    let message = try await inbox.getMessage(at: i)
    print("Subject: \(message.subject ?? "No subject")")
}

try await store.disconnect()
```

## Protocol Logging

Debug POP3 conversations:

```swift
let logger = ConsoleProtocolLogger()
let store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true,
    protocolLogger: logger
)
```

Example output:
```
S: +OK POP3 server ready
C: USER user@example.com
S: +OK
C: PASS ********
S: +OK Logged in
C: STAT
S: +OK 5 12345
C: LIST
S: +OK 5 messages
S: 1 2500
S: 2 3000
...
```

## Best Practices

1. **Use UIDL for tracking** - Message numbers change; UIDs don't
2. **Download headers first** - Use TOP to preview before full download
3. **Handle connection drops** - POP3 doesn't support resuming
4. **Be careful with DELETE** - Deletions are permanent after QUIT
5. **Use RESET if needed** - Undo deletions before disconnecting
6. **Consider IMAP** - For anything beyond simple download workflows
