# Working with IMAP

Access mailboxes, manage folders, search messages, and synchronize state with IMAP.

## Overview

IMAP (Internet Message Access Protocol) provides full mailbox access with support for folders, searching, flags, and multi-device synchronization. MailFoundation implements IMAP4rev1 with over 50 protocol extensions.

## Connecting to an IMAP Server

### Using ImapMailStore (Recommended)

The ``ImapMailStore`` class provides a high-level API for IMAP operations:

```swift
import MailFoundation

// Create and connect
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true
)

try store.connect()
try store.authenticate(username: "user@example.com", password: "password")

// Work with the store...

try store.disconnect()
```

### Using ImapSession (Lower Level)

For more control, use ``ImapSession`` directly:

```swift
let transport = try TransportFactory.make(host: "imap.example.com", port: 993)
let session = ImapSession(transport: transport)

try session.connect()
try session.startTls()  // If not using implicit TLS
try session.login(username: "user", password: "pass")

// Execute commands...

try session.logout()
```

## Working with Folders

### Listing Folders

```swift
// List all folders
let folders = try store.listFolders()
for folder in folders {
    print("Name: \(folder.name), Path: \(folder.fullName)")
    print("Attributes: \(folder.attributes)")
}

// List subscribed folders only
let subscribed = try store.listSubscribedFolders()

// List with status information
let withStatus = try store.listFoldersWithStatus(items: [.messages, .unseen])
for (folder, status) in withStatus {
    print("\(folder.name): \(status.messages ?? 0) messages, \(status.unseen ?? 0) unread")
}
```

### Opening a Folder

```swift
// Get the inbox
let inbox = try store.inbox()

// Open for reading
try inbox.open(access: .readOnly)
print("Messages: \(inbox.count)")
print("Unread: \(inbox.unread)")
print("Recent: \(inbox.recent)")

// Open for modifications
try inbox.open(access: .readWrite)
```

### Creating, Renaming, and Deleting Folders

```swift
// Create a new folder
try store.createFolder(path: "Archive/2024")

// Rename a folder
try store.renameFolder(from: "Old Name", to: "New Name")

// Delete a folder
try store.deleteFolder(path: "Temporary")

// Subscribe/unsubscribe
try store.subscribe(folder: "INBOX.Sent")
try store.unsubscribe(folder: "INBOX.Junk")
```

### Special Folders

IMAP servers may advertise special-use folders. When supported, MailFoundation uses RFC 6154 `SPECIAL-USE` (or Gmail `XLIST`) during authentication to populate these attributes:

```swift
let folders = try store.listFolders()

for folder in folders {
    if folder.hasAttribute(.sent) {
        print("Sent folder: \(folder.name)")
    }
    if folder.hasAttribute(.trash) {
        print("Trash folder: \(folder.name)")
    }
    if folder.hasAttribute(.drafts) {
        print("Drafts folder: \(folder.name)")
    }
}
```

## Fetching Messages

### Message Summaries

Fetch lightweight message metadata without downloading full content:

```swift
let inbox = try store.inbox()
try inbox.open(access: .readOnly)

// Fetch summaries for messages 1-50
let summaries = try inbox.fetchSummaries(
    range: 1...50,
    items: [.envelope, .flags, .size, .uid]
)

for summary in summaries {
    let envelope = summary.envelope
    print("From: \(envelope?.from.first?.address ?? "unknown")")
    print("Subject: \(envelope?.subject ?? "No subject")")
    print("Date: \(envelope?.date?.description ?? "unknown")")
    print("Size: \(summary.size ?? 0) bytes")
    print("Flags: \(summary.flags)")
    print("---")
}
```

### Preview Text

Fetch message preview snippets using the IMAP PREVIEW extension when available,
falling back to a BODY.PEEK[TEXT] preview when it isn't:

```swift
let request = FetchRequest(items: [.envelope, .previewText])
let summaries = try inbox.fetchSummaries(range: 1...50, request: request)

for summary in summaries {
    print(summary.previewText ?? "")
}
```

To request lazy previews (PREVIEW (LAZY)) when supported by the server:

```swift
let request = FetchRequest(items: [.previewText], previewOptions: .lazy)
let summaries = try inbox.fetchSummaries(range: 1...50, request: request)
```

### Fetch by UID

```swift
// Fetch specific UIDs
let uids = UniqueIdSet([UniqueId(id: 100), UniqueId(id: 101), UniqueId(id: 102)])
let summaries = try inbox.uidFetchSummaries(uids: uids, items: [.envelope, .flags])
```

### Body Structure

Examine the MIME structure of a message:

```swift
let summaries = try inbox.fetchSummaries(range: 1...1, items: [.bodyStructure])

if let structure = summaries.first?.bodyStructure {
    switch structure {
    case .singlePart(let part):
        print("Single part: \(part.mediaType)/\(part.mediaSubtype)")
    case .multipart(let multi):
        print("Multipart: \(multi.mediaSubtype)")
        for (index, subpart) in multi.parts.enumerated() {
            print("  Part \(index + 1): \(subpart)")
        }
    }
}
```

### Downloading Message Bodies

```swift
// Fetch the full message
let message = try inbox.getMessage(uid: UniqueId(id: 100))

// Fetch a specific body part
let bodyData = try inbox.getBodyPart(uid: UniqueId(id: 100), section: "1.2")

// Fetch with partial range (for large attachments)
let partial = try inbox.getBodyPart(
    uid: UniqueId(id: 100),
    section: "2",
    offset: 0,
    length: 1024  // First 1KB only
)
```

## Searching Messages

### Basic Searches

```swift
let inbox = try store.inbox()
try inbox.open(access: .readOnly)

// Search for unread messages
let unread = try inbox.search(query: .unseen)
print("Found \(unread.count) unread messages")

// Search by subject
let results = try inbox.search(query: .subject("meeting"))

// Search by sender
let fromBoss = try inbox.search(query: .from("boss@example.com"))
```

### Complex Queries

Build sophisticated queries using ``SearchQuery``:

```swift
// Messages from last week that are unread
let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
let query = SearchQuery.since(lastWeek).and(.unseen)
let results = try inbox.search(query: query)

// Messages with attachments larger than 1MB
let largeAttachments = SearchQuery.larger(1_000_000)

// Combine multiple conditions
let complex = SearchQuery
    .from("important@example.com")
    .and(.subject("urgent"))
    .and(.unseen)
    .and(.since(lastWeek))

let matches = try inbox.search(query: complex)
```

### UID Search

Search returns UIDs for more stable references:

```swift
let uids = try inbox.uidSearch(query: .unseen)
for uid in uids {
    print("Unread message UID: \(uid.id)")
}
```

## Sorting Messages

If the server supports the SORT extension:

```swift
// Sort by date descending
let sorted = try inbox.sort(
    query: .all,
    orderBy: [.reverse(.arrival)]
)

// Sort by sender, then by subject
let multiSort = try inbox.sort(
    query: .unseen,
    orderBy: [.from, .subject]
)
```

## Managing Flags

### Reading Flags

```swift
let summaries = try inbox.fetchSummaries(range: 1...10, items: [.flags])

for summary in summaries {
    if summary.flags.contains(.seen) {
        print("Message \(summary.uid?.id ?? 0) is read")
    }
    if summary.flags.contains(.flagged) {
        print("Message \(summary.uid?.id ?? 0) is starred")
    }
}
```

### Modifying Flags

```swift
// Mark messages as read
try inbox.addFlags(uids: uids, flags: [.seen])

// Remove the flagged status
try inbox.removeFlags(uids: uids, flags: [.flagged])

// Set flags (replaces existing)
try inbox.setFlags(uids: uids, flags: [.seen, .answered])

// Add custom flags (keywords)
try inbox.addFlags(uids: uids, flags: [], keywords: ["$Important", "$Work"])
```

## Copying and Moving Messages

```swift
// Copy messages to another folder
let destinationUids = try inbox.copy(uids: sourceUids, to: "Archive")

// Move messages (requires MOVE extension or copy + delete)
try inbox.move(uids: sourceUids, to: "Archive")
```

## Deleting Messages

IMAP deletion is a two-step process:

```swift
// 1. Mark messages as deleted
try inbox.addFlags(uids: uidsToDelete, flags: [.deleted])

// 2. Expunge to permanently remove
try inbox.expunge()

// Or expunge specific UIDs (if server supports UIDPLUS)
try inbox.expunge(uids: uidsToDelete)
```

## IDLE - Push Notifications

Use IDLE for real-time notifications:

```swift
// Start IDLE mode
try session.idle { event in
    switch event {
    case .exists(let count):
        print("New message! Total: \(count)")
    case .expunge(let sequenceNumber):
        print("Message \(sequenceNumber) was deleted")
    case .flags(let sequenceNumber, let flags):
        print("Flags changed for message \(sequenceNumber)")
    case .alert(let message):
        print("Server alert: \(message)")
    }
}

// Stop IDLE (call from another context)
try session.done()
```

## QRESYNC - Efficient Synchronization

For efficient sync with cached state:

```swift
// Enable QRESYNC
try session.enable(capabilities: [.qresync])

// Select with known state
let state = try session.select(
    mailbox: "INBOX",
    uidValidity: knownUidValidity,
    highestModSeq: knownModSeq,
    knownUids: cachedUids
)

// Server returns only changes since last sync
for vanished in state.vanished {
    print("Message \(vanished) was deleted")
}
for change in state.flagChanges {
    print("Flags changed for \(change.uid)")
}
```

## Quotas

Check mailbox storage quotas:

```swift
let quotaRoot = try session.getQuotaRoot(mailbox: "INBOX")
print("Quota root: \(quotaRoot.root)")

for quota in quotaRoot.quotas {
    print("Resource: \(quota.resource)")
    print("Usage: \(quota.usage) / \(quota.limit)")
}
```

## Access Control Lists (ACL)

Manage folder permissions:

```swift
// Get ACL for a folder
let acl = try session.getAcl(mailbox: "Shared")
for entry in acl {
    print("User: \(entry.identifier), Rights: \(entry.rights)")
}

// Set ACL
try session.setAcl(mailbox: "Shared", identifier: "user@example.com", rights: "lrs")

// Get my rights
let myRights = try session.myRights(mailbox: "Shared")
print("My rights: \(myRights)")
```

## Namespaces

Discover folder namespaces:

```swift
let namespaces = try session.namespace()

print("Personal folders:")
for ns in namespaces.personal {
    print("  Prefix: \(ns.prefix), Delimiter: \(ns.delimiter ?? "none")")
}

print("Shared folders:")
for ns in namespaces.shared {
    print("  Prefix: \(ns.prefix), Delimiter: \(ns.delimiter ?? "none")")
}
```

## Server Identification

Exchange client/server identity:

```swift
// Send client ID
let serverInfo = try session.id(clientInfo: [
    "name": "MyApp",
    "version": "1.0"
])

print("Server: \(serverInfo["name"] ?? "unknown")")
print("Version: \(serverInfo["version"] ?? "unknown")")
```

## Error Handling

```swift
do {
    try inbox.open(access: .readWrite)
} catch let error as ImapMailStoreError {
    switch error {
    case .folderNotFound(let name):
        print("Folder '\(name)' does not exist")
    case .notAuthenticated:
        print("Not logged in")
    case .notConnected:
        print("Not connected to server")
    default:
        print("IMAP error: \(error)")
    }
}
```
