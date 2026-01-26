# Getting Started

Learn how to add MailFoundation to your project and perform basic email operations.

## Overview

MailFoundation provides everything you need to send and receive email in Swift applications. This guide walks you through installation, basic configuration, and your first email operations.

## Adding MailFoundation to Your Project

Add MailFoundation as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/example/MailFoundation.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: ["MailFoundation"]
    )
]
```

## Your First IMAP Connection

Here's how to connect to an IMAP server and list folders:

```swift
import MailFoundation

// Create a mail store
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true
)

// Connect and authenticate
try store.connect()
try store.authenticate(username: "user@example.com", password: "password")

// List all folders
let folders = try store.listFolders()
for folder in folders {
    print("Folder: \(folder.name)")
}

// Open inbox and get message count
let inbox = try store.inbox()
try inbox.open(access: .readOnly)
print("Messages: \(inbox.count)")

// Disconnect
try store.disconnect()
```

## Your First SMTP Message

Sending an email with SMTP:

```swift
import MailFoundation
import MimeFoundation

// Create the message
let message = MimeMessage()
message.from = [MailboxAddress(name: "Sender", address: "sender@example.com")]
message.to = [MailboxAddress(name: "Recipient", address: "recipient@example.com")]
message.subject = "Hello from MailFoundation"
message.body = TextPart(text: "This is my first email!")

// Create transport and send
let transport = try SmtpTransport.make(
    host: "smtp.example.com",
    port: 587,
    useTls: false  // Will use STARTTLS
)

try transport.connect()
try transport.authenticate(username: "user@example.com", password: "password")
try transport.send(message)
try transport.disconnect()
```

## Using Async/Await

MailFoundation provides full async support. Here's the async version:

```swift
import MailFoundation

// Create an async mail store
let store = try await AsyncImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true
)

// Connect and authenticate
try await store.connect()
try await store.authenticate(username: "user@example.com", password: "password")

// Get inbox folder
let inbox = try await store.inbox()
try await inbox.open(access: .readOnly)

// Fetch message summaries
let summaries = try await inbox.fetchSummaries(
    range: 1...10,
    items: [.envelope, .flags]
)

for summary in summaries {
    print("Subject: \(summary.envelope?.subject ?? "No subject")")
}

try await store.disconnect()
```

## Retrieving Messages with POP3

For simple message retrieval, POP3 is straightforward:

```swift
import MailFoundation

let store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true
)

try store.connect()
try store.authenticate(username: "user@example.com", password: "password")

// Get the inbox (POP3 only has one folder)
let inbox = try store.inbox()
try inbox.open()

// Get message count
print("Messages: \(inbox.count)")

// Retrieve a message
if inbox.count > 0 {
    let message = try inbox.getMessage(at: 0)
    print("Subject: \(message.subject ?? "No subject")")
}

try store.disconnect()
```

## Choosing the Right Protocol

| Protocol | Use Case | Features |
|----------|----------|----------|
| **IMAP** | Full mailbox management | Folders, search, flags, sync |
| **SMTP** | Sending email | Delivery receipts, pipelining |
| **POP3** | Simple retrieval | Download and delete |

- Use **IMAP** when you need full mailbox access, searching, or multi-device sync
- Use **SMTP** for sending email (it's the only option for outgoing mail)
- Use **POP3** when you only need to download messages for local storage

## Next Steps

- <doc:Authentication> - Learn about OAuth2 and other auth methods
- <doc:WorkingWithIMAP> - Deep dive into IMAP features
- <doc:WorkingWithSMTP> - Master email sending
- <doc:AsyncPatterns> - Best practices for async code
