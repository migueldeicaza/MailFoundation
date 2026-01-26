# Async Patterns

Best practices for using MailFoundation with Swift concurrency.

## Overview

MailFoundation provides full async/await support with actor-based session management. This guide covers best practices for concurrent email operations, error handling, and integration with SwiftUI and other async contexts.

## Async vs Sync APIs

MailFoundation offers parallel APIs for sync and async usage:

| Sync | Async |
|------|-------|
| `ImapMailStore` | `AsyncImapMailStore` |
| `ImapSession` | `AsyncImapSession` |
| `SmtpTransport` | `AsyncSmtpTransport` |
| `SmtpSession` | `AsyncSmtpSession` |
| `Pop3MailStore` | `AsyncPop3MailStore` |
| `Pop3Session` | `AsyncPop3Session` |

Choose async APIs when:
- Building SwiftUI applications
- Handling multiple connections concurrently
- Avoiding blocking the main thread
- Using other async code

## Basic Async Usage

### Connecting and Authenticating

```swift
import MailFoundation

func checkMail() async throws {
    let store = try await AsyncImapMailStore.make(
        host: "imap.example.com",
        port: 993,
        useTls: true
    )

    try await store.connect()
    try await store.authenticate(username: "user@example.com", password: "password")

    let inbox = try await store.inbox()
    try await inbox.open(access: .readOnly)

    print("You have \(inbox.count) messages")

    try await store.disconnect()
}
```

### Sending Email

```swift
func sendEmail(message: MimeMessage) async throws {
    let transport = try await AsyncSmtpTransport.make(
        host: "smtp.example.com",
        port: 587
    )

    try await transport.connect()
    try await transport.authenticate(username: "user", password: "pass")
    try await transport.send(message)
    try await transport.disconnect()
}
```

## Actor-Based Sessions

Async sessions are implemented as Swift actors, ensuring thread-safe access:

```swift
// AsyncImapSession is an actor
let session = AsyncImapSession(transport: transport)

// All operations are automatically serialized
try await session.connect()
try await session.login(username: "user", password: "pass")

// Safe to call from any context
Task {
    let messages = try await session.search(query: .unseen)
}
```

## Concurrent Operations

### Parallel Fetches

Fetch from multiple folders concurrently:

```swift
func fetchFromMultipleFolders() async throws -> [String: [MessageSummary]] {
    let store = try await AsyncImapMailStore.make(...)
    try await store.connect()
    try await store.authenticate(...)

    // Fetch from multiple folders in parallel
    async let inboxSummaries = fetchFolder(store: store, name: "INBOX")
    async let sentSummaries = fetchFolder(store: store, name: "Sent")
    async let draftsSummaries = fetchFolder(store: store, name: "Drafts")

    // Wait for all results
    let results = try await [
        "INBOX": inboxSummaries,
        "Sent": sentSummaries,
        "Drafts": draftsSummaries
    ]

    try await store.disconnect()
    return results
}

func fetchFolder(store: AsyncImapMailStore, name: String) async throws -> [MessageSummary] {
    let folder = try await store.folder(named: name)
    try await folder.open(access: .readOnly)
    return try await folder.fetchSummaries(range: 1...50, items: [.envelope])
}
```

> Note: IMAP protocol requires commands to be serialized on a single connection. For true parallelism, use multiple connections via `ConnectionPool`.

### Task Groups

Process multiple messages concurrently:

```swift
func processMessages(uids: [UniqueId]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for uid in uids {
            group.addTask {
                try await processMessage(uid: uid)
            }
        }

        // Wait for all tasks
        try await group.waitForAll()
    }
}
```

## Structured Concurrency

### Using withCheckedThrowingContinuation

Bridge callback-based APIs:

```swift
func fetchMessageAsync(uid: UniqueId) async throws -> MimeMessage {
    try await withCheckedThrowingContinuation { continuation in
        // Legacy callback-based API
        fetchMessageWithCallback(uid: uid) { result in
            switch result {
            case .success(let message):
                continuation.resume(returning: message)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
```

### Cancellation Support

Handle task cancellation gracefully:

```swift
func fetchAllMessages() async throws -> [MimeMessage] {
    var messages: [MimeMessage] = []

    for uid in uids {
        // Check for cancellation
        try Task.checkCancellation()

        let message = try await inbox.getMessage(uid: uid)
        messages.append(message)
    }

    return messages
}

// Usage with timeout
let task = Task {
    try await fetchAllMessages()
}

// Cancel after 30 seconds
Task {
    try await Task.sleep(nanoseconds: 30_000_000_000)
    task.cancel()
}

do {
    let messages = try await task.value
} catch is CancellationError {
    print("Fetch was cancelled")
}
```

## Error Handling

### Async Error Patterns

```swift
func checkMailSafely() async {
    do {
        let store = try await AsyncImapMailStore.make(...)
        try await store.connect()
        try await store.authenticate(...)

        // Work with store...

        try await store.disconnect()
    } catch let error as SessionError {
        switch error {
        case .connectionFailed(let underlying):
            print("Connection failed: \(underlying)")
        case .authenticationFailed(let message):
            print("Auth failed: \(message)")
        case .timeout:
            print("Operation timed out")
        default:
            print("Session error: \(error)")
        }
    } catch {
        print("Unexpected error: \(error)")
    }
}
```

### Result-Based Patterns

```swift
func fetchInboxCount() async -> Result<Int, Error> {
    do {
        let store = try await AsyncImapMailStore.make(...)
        try await store.connect()
        try await store.authenticate(...)

        let inbox = try await store.inbox()
        try await inbox.open(access: .readOnly)
        let count = inbox.count

        try await store.disconnect()
        return .success(count)
    } catch {
        return .failure(error)
    }
}
```

## SwiftUI Integration

### Observable Mail Service

```swift
import SwiftUI
import MailFoundation

@MainActor
class MailService: ObservableObject {
    @Published var messages: [MessageSummary] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var store: AsyncImapMailStore?

    func connect(host: String, username: String, password: String) async {
        isLoading = true
        error = nil

        do {
            store = try await AsyncImapMailStore.make(host: host, port: 993, useTls: true)
            try await store?.connect()
            try await store?.authenticate(username: username, password: password)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func fetchInbox() async {
        guard let store = store else { return }

        isLoading = true
        error = nil

        do {
            let inbox = try await store.inbox()
            try await inbox.open(access: .readOnly)
            messages = try await inbox.fetchSummaries(range: 1...50, items: [.envelope, .flags])
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func disconnect() async {
        try? await store?.disconnect()
        store = nil
    }
}
```

### SwiftUI View

```swift
struct MailView: View {
    @StateObject private var mailService = MailService()

    var body: some View {
        NavigationView {
            Group {
                if mailService.isLoading {
                    ProgressView("Loading...")
                } else if let error = mailService.error {
                    Text("Error: \(error.localizedDescription)")
                } else {
                    List(mailService.messages, id: \.uid) { message in
                        VStack(alignment: .leading) {
                            Text(message.envelope?.subject ?? "No subject")
                                .font(.headline)
                            Text(message.envelope?.from.first?.address ?? "Unknown")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .task {
                await mailService.connect(
                    host: "imap.example.com",
                    username: "user@example.com",
                    password: "password"
                )
                await mailService.fetchInbox()
            }
            .onDisappear {
                Task {
                    await mailService.disconnect()
                }
            }
        }
    }
}
```

## Background Tasks

### Long-Running Sync

```swift
func backgroundSync() async {
    // Run indefinitely
    while !Task.isCancelled {
        do {
            try await syncMail()
        } catch {
            print("Sync error: \(error)")
        }

        // Wait before next sync
        try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
    }
}

// Start background task
let syncTask = Task(priority: .background) {
    await backgroundSync()
}

// Stop when needed
syncTask.cancel()
```

### IDLE Push Notifications

```swift
func listenForNewMail() async throws {
    let session = try await AsyncImapSession.make(...)
    try await session.connect()
    try await session.login(...)
    try await session.select(mailbox: "INBOX")

    // Start IDLE loop
    while !Task.isCancelled {
        try await session.idle { event in
            switch event {
            case .exists(let count):
                await MainActor.run {
                    // Notify UI of new message
                    NotificationCenter.default.post(
                        name: .newMailArrived,
                        object: nil,
                        userInfo: ["count": count]
                    )
                }
            default:
                break
            }
        }

        // Refresh IDLE every 29 minutes (before server timeout)
    }
}

extension Notification.Name {
    static let newMailArrived = Notification.Name("newMailArrived")
}
```

## Performance Tips

### 1. Reuse Connections

Don't create new connections for each operation:

```swift
// Bad - creates new connection each time
func checkUnread() async throws -> Int {
    let store = try await AsyncImapMailStore.make(...)
    try await store.connect()
    // ...
    try await store.disconnect()
    return count
}

// Good - reuse connection
class MailClient {
    private var store: AsyncImapMailStore?

    func ensureConnected() async throws {
        if store == nil {
            store = try await AsyncImapMailStore.make(...)
            try await store?.connect()
            try await store?.authenticate(...)
        }
    }

    func checkUnread() async throws -> Int {
        try await ensureConnected()
        // Use existing connection
    }
}
```

### 2. Fetch Only What You Need

```swift
// Bad - fetches everything
let summaries = try await inbox.fetchSummaries(
    range: 1...1000,
    items: [.all]
)

// Good - fetch only needed fields
let summaries = try await inbox.fetchSummaries(
    range: 1...50,  // Paginate
    items: [.envelope, .flags, .uid]  // Only what's needed
)
```

### 3. Use UID Ranges

```swift
// Bad - fetch all then filter
let all = try await inbox.uidFetchSummaries(uids: allUids, items: [.envelope])
let filtered = all.filter { $0.envelope?.subject?.contains("important") ?? false }

// Good - let server filter
let uids = try await inbox.uidSearch(query: .subject("important"))
let filtered = try await inbox.uidFetchSummaries(uids: uids, items: [.envelope])
```

### 4. Batch Operations

```swift
// Bad - individual operations
for uid in uidsToDelete {
    try await inbox.addFlags(uids: UniqueIdSet([uid]), flags: [.deleted])
}

// Good - batch operation
try await inbox.addFlags(uids: UniqueIdSet(uidsToDelete), flags: [.deleted])
```

## Testing Async Code

```swift
import XCTest
@testable import MailFoundation

final class MailTests: XCTestCase {
    func testFetchInbox() async throws {
        let store = try await AsyncImapMailStore.make(
            host: "localhost",
            port: 10993,
            useTls: false
        )

        try await store.connect()
        try await store.authenticate(username: "test", password: "test")

        let inbox = try await store.inbox()
        try await inbox.open(access: .readOnly)

        XCTAssertGreaterThan(inbox.count, 0)

        try await store.disconnect()
    }

    func testWithTimeout() async throws {
        // Test with timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.longRunningTest()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                throw TimeoutError()
            }

            // First to complete wins
            try await group.next()
            group.cancelAll()
        }
    }
}

struct TimeoutError: Error {}
```
