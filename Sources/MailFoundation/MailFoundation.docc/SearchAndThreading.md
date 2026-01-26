# Search and Threading

Build search queries and organize messages into conversation threads.

## Overview

MailFoundation provides powerful tools for finding and organizing email messages. The ``SearchQuery`` type enables building complex IMAP search queries, while ``MessageThreader`` organizes messages into conversation threads.

## Building Search Queries

### Basic Queries

```swift
import MailFoundation

// All messages
let all = SearchQuery.all

// Unread messages
let unread = SearchQuery.unseen

// Flagged/starred messages
let starred = SearchQuery.flagged

// Deleted messages
let deleted = SearchQuery.deleted

// Draft messages
let drafts = SearchQuery.draft

// Recent messages (new since last check)
let recent = SearchQuery.recent

// New messages (recent and unseen)
let new = SearchQuery.new

// Answered/replied messages
let replied = SearchQuery.answered
```

### Text Searches

```swift
// Search in subject
let subjectMatch = SearchQuery.subject("meeting")

// Search in body
let bodyMatch = SearchQuery.body("project update")

// Search in any text (subject, body, headers)
let textMatch = SearchQuery.text("important")

// Search specific header
let headerMatch = SearchQuery.header("X-Priority", "1")
```

### Address Searches

```swift
// From a specific sender
let fromBoss = SearchQuery.from("boss@example.com")

// To a specific recipient
let toMe = SearchQuery.to("me@example.com")

// CC'd to someone
let ccTeam = SearchQuery.cc("team@example.com")

// BCC'd (if visible)
let bccHidden = SearchQuery.bcc("secret@example.com")
```

### Date Searches

```swift
let calendar = Calendar.current
let today = Date()
let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!

// Messages received on a specific date
let onDate = SearchQuery.on(lastWeek)

// Messages received since a date
let sinceDate = SearchQuery.since(lastWeek)

// Messages received before a date
let beforeDate = SearchQuery.before(lastMonth)

// Messages sent (Date header) on/since/before
let sentOn = SearchQuery.sentOn(lastWeek)
let sentSince = SearchQuery.sentSince(lastWeek)
let sentBefore = SearchQuery.sentBefore(lastMonth)
```

### Size Searches

```swift
// Messages larger than 1MB
let large = SearchQuery.larger(1_000_000)

// Messages smaller than 10KB
let small = SearchQuery.smaller(10_000)
```

### UID Searches

```swift
// Specific UID
let uid = SearchQuery.uid(UniqueId(id: 12345))

// UID range
let uidRange = SearchQuery.uid(UniqueIdRange(start: UniqueId(id: 100), end: UniqueId(id: 200)))

// UID set
var uidSet = UniqueIdSet()
uidSet.add(UniqueId(id: 1))
uidSet.add(UniqueId(id: 5))
uidSet.add(UniqueId(id: 10))
let uids = SearchQuery.uid(uidSet)
```

### Combining Queries

```swift
// AND - both conditions must match
let unreadFromBoss = SearchQuery.from("boss@example.com").and(.unseen)

// OR - either condition matches
let urgentOrFlagged = SearchQuery.subject("URGENT").or(.flagged)

// NOT - negate a condition
let notSpam = SearchQuery.not(.header("X-Spam-Status", "Yes"))

// Complex combinations
let important = SearchQuery
    .from("boss@example.com")
    .or(.from("ceo@example.com"))
    .and(.unseen)
    .and(.since(lastWeek))
```

### Chained Queries

The fluent API makes complex queries readable:

```swift
let query = SearchQuery
    .unseen
    .and(.since(lastWeek))
    .and(.from("important@example.com"))
    .and(.not(.deleted))
    .and(.larger(1000))
```

## Executing Searches

### IMAP Search

```swift
let inbox = try store.inbox()
try inbox.open(access: .readOnly)

// Search returns message numbers
let results = try inbox.search(query: .unseen)
print("Found \(results.count) unread messages")

// UID search returns UIDs (more stable)
let uids = try inbox.uidSearch(query: .unseen)
for uid in uids {
    print("Unread message UID: \(uid.id)")
}
```

### Search with Fetch

Combine search and fetch for efficiency:

```swift
// Search and fetch in one operation
let uids = try inbox.uidSearch(query: .unseen)
let summaries = try inbox.uidFetchSummaries(
    uids: uids,
    items: [.envelope, .flags]
)

for summary in summaries {
    print("Subject: \(summary.envelope?.subject ?? "No subject")")
}
```

## Sorting Messages

### Server-Side Sort

If the server supports the SORT extension:

```swift
// Sort by arrival date, newest first
let sorted = try inbox.sort(
    query: .all,
    orderBy: [.reverse(.arrival)]
)

// Sort by sender, then by date
let multiSort = try inbox.sort(
    query: .unseen,
    orderBy: [.from, .arrival]
)

// Available sort criteria
let criteria: [OrderBy] = [
    .arrival,      // Internal date
    .date,         // Date header
    .from,         // From address
    .to,           // To address
    .cc,           // CC address
    .subject,      // Subject (normalized)
    .size,         // Message size

    // Reverse any criteria
    .reverse(.arrival),
    .reverse(.date)
]
```

### Client-Side Sort

Use ``MessageSorter`` when server SORT isn't available:

```swift
let summaries = try inbox.fetchSummaries(range: 1...100, items: [.envelope, .size])

// Sort by date descending
let byDate = MessageSorter.sort(summaries, by: [.reverse(.date)])

// Sort by sender, then subject
let bySender = MessageSorter.sort(summaries, by: [.from, .subject])
```

## Message Threading

Organize messages into conversation threads.

### Thread Algorithms

MailFoundation supports two threading algorithms:

| Algorithm | Description |
|-----------|-------------|
| **OrderedSubject** | Groups by normalized subject |
| **References** | Uses Message-ID and References headers |

### References Threading (Recommended)

```swift
let summaries = try inbox.fetchSummaries(
    range: 1...500,
    items: [.envelope, .references, .uid]
)

// Build thread tree
let threads = MessageThreader.thread(summaries, algorithm: .references)

// Each thread is a root message with replies
for thread in threads {
    printThread(thread, indent: 0)
}

func printThread(_ thread: MessageThread, indent: Int) {
    let prefix = String(repeating: "  ", count: indent)
    let subject = thread.message?.envelope?.subject ?? "No subject"
    print("\(prefix)- \(subject)")

    for child in thread.children {
        printThread(child, indent: indent + 1)
    }
}
```

Output:
```
- Project Update
  - Re: Project Update
    - Re: Project Update
  - Re: Project Update (different branch)
- Meeting Tomorrow
  - Re: Meeting Tomorrow
```

### OrderedSubject Threading

For servers without References support:

```swift
let threads = MessageThreader.thread(summaries, algorithm: .orderedSubject)
```

This groups messages by normalized subject (removing Re:, Fwd:, etc.).

### Server-Side Threading

If the server supports the THREAD extension:

```swift
// Check for THREAD capability
if session.capabilities.contains(.threadReferences) {
    let threadRoots = try session.thread(
        algorithm: "REFERENCES",
        query: .all
    )
}
```

## Subject Normalization

MailFoundation normalizes subjects for comparison:

```swift
let subject = "Re: Fwd: RE: Meeting Tomorrow [was: Schedule Change]"

let threadable = ThreadableSubject(subject)

print(threadable.normalized)  // "meeting tomorrow"
print(threadable.isReply)     // true
print(threadable.replyDepth)  // 3 (three Re:/Fwd: prefixes)
```

### Normalization Rules

1. Remove leading/trailing whitespace
2. Remove Re:, Fwd:, FW: prefixes (case-insensitive)
3. Remove [bracketed] content (mailing list tags)
4. Lowercase for comparison

## Search Query Optimization

MailFoundation automatically optimizes queries:

```swift
// Before optimization
let query = SearchQuery.unseen.and(.all).and(.not(.not(.flagged)))

// After optimization (equivalent)
// SearchQuery.unseen.and(.flagged)
```

The optimizer:
- Removes redundant `.all` terms
- Eliminates double negations
- Flattens nested AND/OR trees
- Removes duplicate terms

## Practical Examples

### Find Unread Messages from VIPs

```swift
let vips = ["boss@example.com", "ceo@example.com", "cto@example.com"]

var query = SearchQuery.unseen

// Build OR chain for VIPs
for (index, vip) in vips.enumerated() {
    if index == 0 {
        query = query.and(.from(vip))
    } else {
        query = query.or(.from(vip))
    }
}

let results = try inbox.uidSearch(query: query)
```

### Find Large Attachments

```swift
// Messages larger than 5MB from last month
let query = SearchQuery
    .larger(5_000_000)
    .and(.since(lastMonth))

let largeMessages = try inbox.uidSearch(query: query)
```

### Find Conversation

```swift
// Find all messages in a conversation by subject
func findConversation(subject: String) throws -> [MessageSummary] {
    let normalized = ThreadableSubject(subject).normalized

    // Search for subject and common reply patterns
    let query = SearchQuery
        .subject(normalized)
        .or(.subject("Re: \(normalized)"))
        .or(.subject("Fwd: \(normalized)"))

    let uids = try inbox.uidSearch(query: query)
    return try inbox.uidFetchSummaries(uids: uids, items: [.envelope, .references])
}

// Or use Message-ID threading
func findConversationByMessageId(messageId: String) throws -> [MessageSummary] {
    // Search for messages that reference this Message-ID
    let query = SearchQuery.header("References", messageId)
        .or(.header("In-Reply-To", messageId))
        .or(.header("Message-ID", messageId))

    let uids = try inbox.uidSearch(query: query)
    return try inbox.uidFetchSummaries(uids: uids, items: [.envelope, .references])
}
```

### Archive Old Messages

```swift
// Find messages older than 1 year, excluding flagged
let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today)!

let query = SearchQuery
    .before(oneYearAgo)
    .and(.not(.flagged))
    .and(.seen)

let oldMessages = try inbox.uidSearch(query: query)

// Move to archive
try inbox.move(uids: oldMessages, to: "Archive")
```
