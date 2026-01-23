import Foundation
import Testing
@testable import MailFoundation
import SwiftMimeKit

@Test("UniqueId basics")
func uniqueIdBasics() {
    let uid = UniqueId(id: 42)
    #expect(uid.isValid)
    #expect(uid.id == 42)
    #expect(uid.validity == 0)
    #expect(UniqueId.invalid.isValid == false)
    #expect(UniqueId.minValue < UniqueId.maxValue)
}

@Test("UniqueId parsing")
func uniqueIdParsing() throws {
    #expect(UniqueId.tryParse("1") != nil)
    #expect(UniqueId.tryParse("0") == nil)
    #expect(UniqueId.tryParse("abc") == nil)
    #expect(UniqueId.tryParse("4294967296") == nil)
    #expect(UniqueId.tryParse(" 7 ")?.id == 7)

    let parsed = try UniqueId.parse("12", validity: 9)
    #expect(parsed.id == 12)
    #expect(parsed.validity == 9)
}

@Test("UniqueIdRange parsing")
func uniqueIdRangeParsing() throws {
    let range = try UniqueIdRange.parse("2:4", validity: 7)
    #expect(range.count == 3)
    #expect(range.contains(UniqueId(id: 3)))
    #expect(range.sortOrder == .ascending)
    #expect(range.description == "2:4")

    let anyRange = try UniqueIdRange.parse("2:*")
    #expect(anyRange.description == "2:*")

    let spacedRange = try UniqueIdRange.parse(" 2 : * ")
    #expect(spacedRange.description == "2:*")
    #expect(UniqueIdRange.tryParse("2:") == nil)
}

@Test("UniqueIdSet add and serialize")
func uniqueIdSetAddAndSerialize() throws {
    var set = UniqueIdSet()
    set.add(UniqueId(id: 1))
    set.add(UniqueId(id: 2))
    set.add(UniqueId(id: 3))
    #expect(set.count == 3)
    #expect(set.contains(UniqueId(id: 2)))
    #expect(set.description == "1:3")

    var descending = UniqueIdSet(sortOrder: .descending)
    descending.add(UniqueId(id: 5))
    descending.add(UniqueId(id: 4))
    descending.add(UniqueId(id: 3))
    #expect(descending.description == "5:3")

    let subsets = try descending.serializedSubsets(maxLength: 3)
    #expect(subsets.count >= 1)
}

@Test("UniqueIdSet parsing")
func uniqueIdSetParsing() throws {
    let set = try UniqueIdSet.parse("1:3,5,7:6", validity: 11)
    #expect(set.count == 6)
    #expect(set.validity == 11)
    #expect(set.description == "1:3,5,7:6")

    let starSet = try UniqueIdSet.parse("1:*,*", validity: 0)
    #expect(starSet.description == "1:*,*")

    let spacedSet = try UniqueIdSet.parse("1 : 3 , 5 , 7 : 6")
    #expect(spacedSet.description == "1:3,5,7:6")
    #expect(UniqueIdSet.tryParse("0") == nil)
}

@Test("SequenceSet parsing")
func sequenceSetParsing() throws {
    let set = try SequenceSet.parse("1:3,5,*")
    #expect(set.description == "1:3,5,*")
    #expect(set.contains(1))
    #expect(set.contains(UInt32.max))
    #expect(SequenceSet.tryParse("0") == nil)

    let spaced = try SequenceSet.parse(" 2 : 4 , 6 ")
    #expect(spaced.description == "2:4,6")
}

@Test("UniqueIdRange utilities")
func uniqueIdRangeUtilities() {
    let range = UniqueIdRange(validity: 2, start: 10, end: 12)
    #expect(range.index(of: UniqueId(id: 11)) == 1)
    #expect(range[0].id == 10)

    var buffer = Array(repeating: UniqueId.invalid, count: range.count)
    range.copy(to: &buffer, startingAt: 0)
    #expect(buffer[2].id == 12)
}

@Test("UniqueIdMap mapping")
func uniqueIdMapMapping() {
    let source = [UniqueId(id: 1), UniqueId(id: 2), UniqueId(id: 3)]
    let destination = [UniqueId(id: 10), UniqueId(id: 20)]
    let map = UniqueIdMap(source: source, destination: destination)

    #expect(map.count == 3)
    #expect(map.pairedCount == 2)
    #expect(map.isEmpty == false)
    #expect(map.contains(UniqueId(id: 2)))
    #expect(map.value(for: UniqueId(id: 2))?.id == 20)
    #expect(map.value(for: UniqueId(id: 3)) == nil)

    let dict = map.toDictionary()
    #expect(dict[UniqueId(id: 1)]?.id == 10)

    let pairsMap = UniqueIdMap(pairs: [(UniqueId(id: 4), UniqueId(id: 40))])
    #expect(pairsMap.pairs.count == 1)

    let dictMap = UniqueIdMap(dictionary: [UniqueId(id: 2): UniqueId(id: 20), UniqueId(id: 1): UniqueId(id: 10)])
    #expect(dictMap.source.map { $0.id } == [1, 2])

    let appended = dictMap.appending(source: UniqueId(id: 3), destination: UniqueId(id: 30))
    #expect(appended.destination.last?.id == 30)

    let merged = dictMap.appending(contentsOf: pairsMap)
    #expect(merged.destination.last?.id == 40)
}

@Test("IMAP command helpers")
func imapCommandHelpers() throws {
    let seqSet = try SequenceSet.parse("1:3")
    let fetch = ImapCommandKind.fetch(seqSet, items: "FLAGS").command(tag: "A0001")
    #expect(fetch.serialized == "A0001 FETCH 1:3 FLAGS\r\n")

    let uidSet = UniqueIdSet([UniqueId(id: 1), UniqueId(id: 2)])
    let uidFetch = ImapCommandKind.uidFetch(uidSet, items: "FLAGS").command(tag: "A0002")
    #expect(uidFetch.serialized == "A0002 UID FETCH \(uidSet.description) FLAGS\r\n")

    let query = SearchQuery.from("alice@example.com").and(.unseen)
    let search = ImapCommandKind.search(query).command(tag: "A0003")
    #expect(search.serialized == "A0003 SEARCH FROM \"alice@example.com\" UNSEEN\r\n")
}

@Test("IMAP mailbox list parsing")
func imapMailboxListParsing() {
    let listLine = "* LIST (\\HasNoChildren) \"/\" \"INBOX\""
    let list = ImapMailboxListResponse.parse(listLine)
    #expect(list?.kind == .list)
    #expect(list?.attributes == ["\\HasNoChildren"])
    #expect(list?.delimiter == "/")
    #expect(list?.name == "INBOX")
    #expect(list?.decodedName == "INBOX")

    let mailbox = list?.toMailbox()
    #expect(mailbox?.hasAttribute(.hasNoChildren) == true)
    #expect(mailbox?.isSelectable == true)

    let lsubLine = "* LSUB () NIL INBOX"
    let lsub = ImapMailboxListResponse.parse(lsubLine)
    #expect(lsub?.kind == .lsub)
    #expect(lsub?.attributes.isEmpty == true)
    #expect(lsub?.delimiter == nil)
    #expect(lsub?.name == "INBOX")

    let specialLine = "* LIST (\\NoSelect \\HasChildren \\All) \"/\" \"[Gmail]\""
    let special = ImapMailboxListResponse.parse(specialLine)?.toMailbox()
    #expect(special?.hasAttribute(.noSelect) == true)
    #expect(special?.hasChildren == true)
    #expect(special?.specialUse == .all)
    #expect(special?.decodedName == "[Gmail]")
}

@Test("IMAP list-status parsing")
func imapListStatusParsing() {
    let line = "* LIST (\\HasNoChildren) \"/\" \"INBOX\" (MESSAGES 2 UIDNEXT 5)"
    let response = ImapListStatusResponse.parse(line)
    #expect(response?.mailbox.name == "INBOX")
    #expect(response?.mailbox.attributes.contains(.hasNoChildren) == true)
    #expect(response?.statusItems["MESSAGES"] == 2)
    #expect(response?.statusItems["UIDNEXT"] == 5)
}

@Test("IMAP MODSEQ/VANISHED parsing")
func imapModSeqVanishedParsing() throws {
    let modseqLine = "* OK [HIGHESTMODSEQ 42] Ok"
    let modseq = ImapModSeqResponse.parse(modseqLine)
    #expect(modseq?.kind == .highest)
    #expect(modseq?.value == 42)

    let modLine = "* OK [MODSEQ 7] Ok"
    let mod = ImapModSeqResponse.parse(modLine)
    #expect(mod?.kind == .modSeq)
    #expect(mod?.value == 7)

    let vanishedLine = "* VANISHED 1:3"
    let vanished = ImapVanishedResponse.parse(vanishedLine)
    #expect(vanished?.earlier == false)
    #expect(vanished?.uids.description == "1:3")

    let earlierLine = "* VANISHED (EARLIER) 4:5"
    let earlier = ImapVanishedResponse.parse(earlierLine)
    #expect(earlier?.earlier == true)
    #expect(earlier?.uids.description == "4:5")
}

@Test("IMAP search set helpers")
func imapSearchSetHelpers() {
    let response = ImapSearchResponse(ids: [1, 2, 3])
    let seq = response.sequenceSet()
    #expect(seq.description == "1:3")
    let uidSet = response.uniqueIdSet(validity: 7)
    #expect(uidSet.validity == 7)
    #expect(uidSet.description == "1:3")
}

@Test("IMAP mailbox status unification")
func imapMailboxStatusUnification() {
    let status = ImapStatusResponse(mailbox: "INBOX", items: ["MESSAGES": 2])
    let listStatusLine = "* LIST (\\HasNoChildren) \"/\" \"INBOX\" (UIDNEXT 5)"
    let listStatus = ImapListStatusResponse.parse(listStatusLine)
    let left = ImapMailboxStatus(status: status)
    guard let listStatus else {
        #expect(Bool(false))
        return
    }
    let right = ImapMailboxStatus(listStatus: listStatus)
    let merged = left.merging(right)
    #expect(merged.items["MESSAGES"] == 2)
    #expect(merged.items["UIDNEXT"] == 5)
    #expect(merged.mailbox?.name == "INBOX")
}

@Test("IMAP bodystructure parsing")
func imapBodyStructureParsing() {
    let singleRaw = "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 12 1)"
    let single = ImapBodyStructure.parse(singleRaw)
    if case let .single(part)? = single {
        #expect(part.type.uppercased() == "TEXT")
        #expect(part.subtype.uppercased() == "PLAIN")
        #expect(part.parameters["CHARSET"] == "UTF-8")
        #expect(part.size == 12)
        #expect(part.lines == 1)
    } else {
        #expect(Bool(false))
    }

    let multiRaw = "((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 12 1)(\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 34 2) \"ALTERNATIVE\" (\"BOUNDARY\" \"abc\"))"
    let multi = ImapBodyStructure.parse(multiRaw)
    if case let .multipart(multipart)? = multi {
        #expect(multipart.parts.count == 2)
        #expect(multipart.subtype.uppercased() == "ALTERNATIVE")
        #expect(multipart.parameters["BOUNDARY"] == "abc")
    } else {
        #expect(Bool(false))
    }

    let extendedRaw = "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 12 1 \"md5hash\" (\"INLINE\" (\"FILENAME\" \"a.txt\")) (\"en\" \"fr\") \"loc\" 99)"
    let extended = ImapBodyStructure.parse(extendedRaw)
    if case let .single(part)? = extended {
        #expect(part.md5 == "md5hash")
        #expect(part.disposition?.type.uppercased() == "INLINE")
        #expect(part.disposition?.parameters["FILENAME"] == "a.txt")
        #expect(part.language == ["en", "fr"])
        #expect(part.location == "loc")
        #expect(part.extensions == ["99"])
    } else {
        #expect(Bool(false))
    }

    let messageRaw = "(\"MESSAGE\" \"RFC822\" (\"NAME\" \"msg\") NIL NIL \"7BIT\" 123 (\"Wed, 01 Jan 2020 00:00:00 +0000\" \"Hello\" ((\"Alice\" NIL \"alice\" \"example.com\")) NIL NIL ((\"Bob\" NIL \"bob\" \"example.com\")) NIL NIL NIL \"<msgid>\") (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 12 1) 10)"
    let message = ImapBodyStructure.parse(messageRaw)
    if case let .single(part)? = message {
        #expect(part.envelopeRaw?.contains("Hello") == true)
        #expect(part.embedded != nil)
        #expect(part.lines == 10)
    } else {
        #expect(Bool(false))
    }

    if let multipart = ImapBodyStructure.parse(multiRaw) {
        let parts = multipart.enumerateParts()
        #expect(parts.map { $0.0 } == ["1", "2"])
        #expect(multipart.part(for: "2")?.subtype.uppercased() == "HTML")
        let section = ImapFetchBodySection(part: [2], subsection: .header)
        if let resolution = multipart.resolve(section: section) {
            if case let .part(id, node) = resolution.scope {
                #expect(id == "2")
                if case .single = node {
                    #expect(resolution.subsection == .header)
                    #expect(resolution.contentType == "TEXT/HTML")
                    #expect(resolution.boundary == nil)
                } else {
                    #expect(Bool(false))
                }
            } else {
                #expect(Bool(false))
            }
        } else {
            #expect(Bool(false))
        }
        if let rootResolution = multipart.resolve(section: .header) {
            #expect(rootResolution.contentType == "MULTIPART/ALTERNATIVE")
            #expect(rootResolution.boundary == "abc")
        } else {
            #expect(Bool(false))
        }
    } else {
        #expect(Bool(false))
    }

    if let embedded = message {
        let parts = embedded.enumerateParts()
        #expect(parts.first?.0 == "1")
        #expect(parts.count >= 2)
        #expect(parts[1].0 == "1.1")
        #expect(embedded.part(for: "1")?.type.uppercased() == "MESSAGE")
        #expect(embedded.part(for: "1.1")?.type.uppercased() == "TEXT")
        if let resolution = embedded.resolve(section: .header) {
            if case .message = resolution.scope {
                #expect(resolution.subsection == .header)
                #expect(resolution.contentType == "MESSAGE/RFC822")
            } else {
                #expect(Bool(false))
            }
        } else {
            #expect(Bool(false))
        }
    } else {
        #expect(Bool(false))
    }
}

@Test("IMAP fetch BODY section helpers")
func imapFetchBodySectionHelpers() {
    let full = ImapFetchBody.section()
    #expect(full == "BODY[]")

    let header = ImapFetchBody.section(.header, peek: true)
    #expect(header == "BODY.PEEK[HEADER]")

    let fields = ImapFetchBody.section(.headerFields(["Subject", "From"]))
    #expect(fields == "BODY[HEADER.FIELDS (Subject From)]")

    let part = ImapFetchBody.section(ImapFetchBodySection(part: [1, 2], subsection: .text))
    #expect(part == "BODY[1.2.TEXT]")

    let partial = ImapFetchBody.section(.text, partial: ImapFetchPartial(start: 0, length: 128))
    #expect(partial == "BODY[TEXT]<0.128>")
}

@Test("IMAP envelope parsing")
func imapEnvelopeParsing() {
    let raw = "(\"Wed, 01 Jan 2020 00:00:00 +0000\" \"Hello\" ((\"Alice\" NIL \"alice\" \"example.com\")) NIL NIL ((\"Bob\" NIL \"bob\" \"example.com\")) NIL NIL NIL \"<msgid>\")"
    let envelope = ImapEnvelope.parse(raw)
    #expect(envelope?.subject == "Hello")
    #expect(envelope?.messageId == "<msgid>")
    if case let .mailbox(from)? = envelope?.from.first {
        #expect(from.address == "alice@example.com")
    } else {
        #expect(Bool(false))
    }
    if case let .mailbox(to)? = envelope?.to.first {
        #expect(to.address == "bob@example.com")
    } else {
        #expect(Bool(false))
    }
}

@Test("IMAP fetch body section parsing")
func imapFetchBodySectionParsing() {
    let section = ImapFetchBodySection.parse("1.2.HEADER")
    #expect(section?.part == [1, 2])
    #expect(section?.subsection == .header)

    let fields = ImapFetchBodySection.parse("HEADER.FIELDS (Subject From)")
    #expect(fields?.part.isEmpty == true)
    #expect(fields?.subsection == .headerFields(["Subject", "From"]))

    let notFields = ImapFetchBodySection.parse("1.TEXT")
    #expect(notFields?.part == [1])
    #expect(notFields?.subsection == .text)
}

@Test("IMAP fetch body section response parsing")
func imapFetchBodySectionResponseParsing() {
    let line = "* 1 FETCH (BODY[HEADER] {5}"
    let message = ImapLiteralMessage(line: line, response: ImapResponse.parse(line), literal: Array("Hello".utf8))
    let parsed = ImapFetchBodySectionResponse.parse(message)
    #expect(parsed?.sequence == 1)
    #expect(parsed?.peek == false)
    #expect(parsed?.section?.subsection == .header)
    #expect(parsed?.data == Array("Hello".utf8))

    let linePeek = "* 2 FETCH (BODY.PEEK[1.2.TEXT]<0.3> {3}"
    let messagePeek = ImapLiteralMessage(line: linePeek, response: ImapResponse.parse(linePeek), literal: Array("abc".utf8))
    let parsedPeek = ImapFetchBodySectionResponse.parse(messagePeek)
    #expect(parsedPeek?.peek == true)
    #expect(parsedPeek?.section?.part == [1, 2])
    #expect(parsedPeek?.section?.subsection == .text)
    #expect(parsedPeek?.partial == ImapFetchPartial(start: 0, length: 3))
}

@Test("IMAP envelope cache")
func imapEnvelopeCache() async {
    let raw = "(\"Wed, 01 Jan 2020 00:00:00 +0000\" \"Hello\" ((\"Alice\" NIL \"alice\" \"example.com\")) NIL NIL ((\"Bob\" NIL \"bob\" \"example.com\")) NIL NIL NIL \"<msgid>\")"
    let cache = ImapEnvelopeCache(maxEntries: 4)
    let first = await cache.envelope(for: raw)
    #expect(first?.subject == "Hello")
    #expect(await cache.count() == 1)
    let second = await cache.envelope(for: raw)
    #expect(second?.messageId == "<msgid>")
    #expect(await cache.count() == 1)
}

@Test("IMAP qresync event parsing")
func imapQresyncEventParsing() {
    let vanishedLine = "* VANISHED (EARLIER) 5:6"
    let vanished = ImapQresyncEvent.parse(vanishedLine)
    #expect(vanished != nil)

    let fetchLine = "* 2 FETCH (UID 44 MODSEQ (7))"
    let fetch = ImapQresyncEvent.parse(fetchLine)
    if case let .fetch(event)? = fetch {
        #expect(event.sequence == 2)
        #expect(event.uid == 44)
        #expect(event.modSeq == 7)
    } else {
        #expect(Bool(false))
    }
}

@Test("IMAP fetch body section collector")
func imapFetchBodySectionCollector() async {
    let collector = ImapFetchBodySectionCollector()
    let line1 = "* 1 FETCH (BODY[HEADER] {5}"
    let msg1 = ImapLiteralMessage(line: line1, response: ImapResponse.parse(line1), literal: Array("Hello".utf8))
    let line2 = "* 1 FETCH (BODY[TEXT] {3}"
    let msg2 = ImapLiteralMessage(line: line2, response: ImapResponse.parse(line2), literal: Array("abc".utf8))
    _ = await collector.ingest(msg1)
    _ = await collector.ingest(msg2)
    let results = await collector.ingest([])
    #expect(results.count == 1)
    #expect(results.first?.sections.count == 2)
    let header = results.first?.section(subsection: .header)
    #expect(header?.data == Array("Hello".utf8))
}

@Test("IMAP idle event parsing")
func imapIdleEventParsing() {
    let exists = ImapIdleEvent.parse("* 3 EXISTS")
    #expect(exists == .exists(3))

    let expunge = ImapIdleEvent.parse("* 4 EXPUNGE")
    #expect(expunge == .expunge(4))

    let recent = ImapIdleEvent.parse("* 1 RECENT")
    #expect(recent == .recent(1))

    let flags = ImapIdleEvent.parse("* FLAGS (\\Seen \\Answered)")
    #expect(flags == .flags(["\\Seen", "\\Answered"]))

    let ok = ImapIdleEvent.parse("* OK [ALERT] Foo")
    #expect(ok != nil)
}

@Test("IMAP idle done command")
func imapIdleDoneCommand() {
    let command = ImapCommandKind.idleDone.command(tag: "A0001")
    #expect(command.serialized == "A0001 DONE\r\n")
}

@Test("IMAP fetch body parser")
func imapFetchBodyParser() {
    let line1 = "* 2 FETCH (BODY[] {5}"
    let msg1 = ImapLiteralMessage(line: line1, response: ImapResponse.parse(line1), literal: Array("Hello".utf8))
    let line2 = "* 3 FETCH (BODY[1] {3}"
    let msg2 = ImapLiteralMessage(line: line2, response: ImapResponse.parse(line2), literal: Array("abc".utf8))
    let results = ImapFetchBodyParser.parse([msg1, msg2])
    #expect(results.count == 2)
    #expect(results.first?.sequence == 2)
}

@Test("IMAP fetch body map")
func imapFetchBodyMap() {
    let line1 = "* 2 FETCH (BODY[] {5}"
    let msg1 = ImapLiteralMessage(line: line1, response: ImapResponse.parse(line1), literal: Array("Hello".utf8))
    let line2 = "* 2 FETCH (BODY[TEXT] {3}"
    let msg2 = ImapLiteralMessage(line: line2, response: ImapResponse.parse(line2), literal: Array("abc".utf8))
    let maps = ImapFetchBodyParser.parseMaps([msg1, msg2])
    #expect(maps.count == 1)
    #expect(maps.first?.body() == Array("Hello".utf8))
    let text = ImapFetchBodySection(subsection: .text)
    #expect(maps.first?.body(section: text) == Array("abc".utf8))
}

@Test("IMAP fetch body map with QRESYNC")
func imapFetchBodyMapWithQresync() {
    let line1 = "* 2 FETCH (BODY[] {5}"
    let msg1 = ImapLiteralMessage(line: line1, response: ImapResponse.parse(line1), literal: Array("Hello".utf8))
    let line2 = "* 2 FETCH (UID 5 MODSEQ (10))"
    let msg2 = ImapLiteralMessage(line: line2, response: ImapResponse.parse(line2), literal: nil)
    let line3 = "* VANISHED 6:7"
    let msg3 = ImapLiteralMessage(line: line3, response: ImapResponse.parse(line3), literal: nil)
    let result = ImapFetchBodyParser.parseMapsWithQresync([msg1, msg2, msg3], validity: 9)
    #expect(result.bodies.count == 1)
    #expect(result.bodies.first?.body() == Array("Hello".utf8))
    #expect(result.qresyncEvents.count == 2)
}

@Test("IMAP mailbox UTF-7 decoding")
func imapMailboxUtf7Decoding() {
    let encoded = "Archive &AOQ- Stuff"
    let decoded = ImapMailboxEncoding.decode(encoded)
    #expect(decoded == "Archive \u{00E4} Stuff")
    let roundTrip = ImapMailboxEncoding.encode(decoded)
    #expect(roundTrip == encoded)
}

@Test("SearchQuery serialization")
func searchQuerySerialization() {
    let query = SearchQuery.from("alice@example.com")
        .and(.subject("Hello"))
        .and(.unseen)
    #expect(query.serialize() == "FROM \"alice@example.com\" SUBJECT \"Hello\" UNSEEN")

    let date = Date(timeIntervalSince1970: 1704153600)
    let dateQuery = SearchQuery.since(date)
    #expect(dateQuery.serialize() == "SINCE 02-Jan-2024")

    let orQuery = SearchQuery.or(.from("a@example.com"), .and([.to("b@example.com"), .subject("c")]))
    #expect(orQuery.serialize() == "OR FROM \"a@example.com\" (TO \"b@example.com\" SUBJECT \"c\")")

    let uidSet = UniqueIdSet([UniqueId(id: 1), UniqueId(id: 2)])
    let uidQuery = SearchQuery.uid(uidSet)
    #expect(uidQuery.serialize() == "UID \(uidSet.description)")

    let headerQuery = SearchQuery.header("X-Test", "value")
    #expect(headerQuery.serialize() == "HEADER \"X-Test\" \"value\"")
}

@Test("MessageFlags options")
func messageFlagsOptions() {
    let flags: MessageFlags = [.seen, .answered, .flagged]
    #expect(flags.contains(.seen))
    #expect(flags.contains(.answered))
    #expect(flags.contains(.flagged))
    #expect(!flags.contains(.deleted))
}

@Test("Envelope encode and parse")
func envelopeEncodeAndParse() throws {
    let envelope = Envelope()
    envelope.subject = "Hello"
    envelope.from.add(MailboxAddress(name: "Alice", address: "alice@example.com"))
    envelope.to.add(MailboxAddress(name: "Bob", address: "bob@example.com"))
    envelope.messageId = "msgid"

    let encoded = envelope.toString()
    let parsed = try Envelope.parse(encoded)

    #expect(parsed.subject == "Hello")
    #expect(parsed.from.count == 1)
    let parsedFrom = parsed.from[parsed.from.startIndex] as? MailboxAddress
    #expect(parsedFrom?.address == "alice@example.com")
    #expect(parsed.messageId == "<msgid>")
    #expect(Envelope.tryParse("NIL") == nil)
    #expect(Envelope.tryParse("nil") == nil)
}

@Test("Envelope literal parsing")
func envelopeLiteralParsing() throws {
    let text = "(\"Wed, 01 Jan 2020 00:00:00 +0000\" {5}\r\nHello NIL NIL NIL NIL NIL NIL NIL NIL)"
    let envelope = try Envelope.parse(text)
    #expect(envelope.subject == "Hello")
}

@Test("Envelope apply headers")
func envelopeApplyHeaders() {
    let envelope = Envelope()
    envelope.apply(headers: [
        "Subject": "=?UTF-8?B?SGVsbG8=?=",
        "From": "Alice <alice@example.com>",
        "Message-Id": "<msgid@example.com>",
        "In-Reply-To": "<reply@example.com>",
        "List-Id": "Example List <list.example.com>",
        "List-Unsubscribe": "<mailto:unsubscribe@example.com>",
        "DKIM-Signature": "v=1; a=rsa-sha256; d=example.com; s=mail;",
        "Authentication-Results": "mx.example.com; spf=pass",
        "Received-SPF": "pass"
    ])
    envelope.apply(header: "DKIM-Signature", value: "v=1; a=rsa-sha256; d=example.com; s=mail2;")
    #expect(envelope.subject == "Hello")
    let from = envelope.from[envelope.from.startIndex] as? MailboxAddress
    #expect(from?.address == "alice@example.com")
    #expect(envelope.messageId == "<msgid@example.com>")
    #expect(envelope.inReplyTo == "<reply@example.com>")
    #expect(envelope.listId == "Example List <list.example.com>")
    #expect(envelope.listUnsubscribe == "<mailto:unsubscribe@example.com>")
    #expect(envelope.dkimSignatures.count == 2)
    #expect(envelope.authenticationResults.first == "mx.example.com; spf=pass")
    #expect(envelope.receivedSpf.first == "pass")
}

@Test("Envelope apply SwiftMimeKit headers")
func envelopeApplySwiftMimeKitHeaders() {
    let headers = [
        Header(field: "Subject", value: "=?UTF-8?B?SGVsbG8=?="),
        Header(field: "From", value: "Alice <alice@example.com>")
    ]
    let envelope = Envelope()
    envelope.apply(headers: headers)
    #expect(envelope.subject == "Hello")
    let from = envelope.from[envelope.from.startIndex] as? MailboxAddress
    #expect(from?.address == "alice@example.com")
}

@Test("Envelope init from HeaderList")
func envelopeInitFromHeaderList() {
    let list = HeaderList()
    list.add(Header(field: "Subject", value: "=?UTF-8?B?SGVsbG8=?="))
    list.add(Header(field: "From", value: "Alice <alice@example.com>"))
    let envelope = Envelope(headers: list)
    #expect(envelope.subject == "Hello")
    let from = envelope.from[envelope.from.startIndex] as? MailboxAddress
    #expect(from?.address == "alice@example.com")
}

@Test("MessageIdList parsing")
func messageIdListParsing() {
    let value = "<id1@example.com> <id2@example.com>"
    let list = MessageIdList.parse(value)
    #expect(list?.ids.count == 2)
    #expect(list?.ids.first == "<id1@example.com>")

    let fallback = MessageIdList.parse("id3@example.com")
    #expect(fallback?.ids == ["id3@example.com"])
}

@Test("References header parsing")
func referencesHeaderParsing() {
    let header = ReferencesHeader.parse("<id1@example.com> <id2@example.com>")
    #expect(header?.ids == ["<id1@example.com>", "<id2@example.com>"])
    #expect(header?.description == "<id1@example.com> <id2@example.com>")
}

@Test("In-Reply-To header parsing")
func inReplyToHeaderParsing() {
    let header = InReplyToHeader.parse("<id3@example.com>")
    #expect(header?.ids == ["<id3@example.com>"])
}

@Test("Address parser helpers")
func addressParserHelpers() throws {
    let list = try AddressParser.parseList("Alice <alice@example.com>, Bob <bob@example.com>")
    #expect(list.count == 2)

    let mailbox = try AddressParser.parseMailbox("Alice <alice@example.com>")
    #expect(mailbox.address == "alice@example.com")
}

@Test("Subject decoder")
func subjectDecoder() {
    let decoded = SubjectDecoder.decode("=?UTF-8?B?SGVsbG8=?=")
    #expect(decoded == "Hello")
}

@Test("Threading references merge")
func threadingReferencesMerge() {
    let threading = ThreadingReferences.merge(inReplyTo: "<id3@example.com>", references: "<id1@example.com> <id2@example.com>")
    #expect(threading?.ids == ["<id1@example.com>", "<id2@example.com>", "<id3@example.com>"])
}

@Test("ProtocolLogger prefixes and redacts")
func protocolLoggerPrefixesAndRedacts() throws {
    final class StaticSecretDetector: AuthenticationSecretDetector {
        private let secretBytes: [UInt8] = Array("secret".utf8)

        func detectSecrets(in buffer: [UInt8], offset: Int, count: Int) -> [AuthenticationSecret] {
            guard count > 0 else { return [] }
            let end = offset + count
            guard end <= buffer.count else { return [] }

            var index = offset
            while index + secretBytes.count <= end {
                if buffer[index..<(index + secretBytes.count)].elementsEqual(secretBytes) {
                    return [AuthenticationSecret(startIndex: index, length: secretBytes.count)]
                }
                index += 1
            }
            return []
        }
    }

    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = false
    logger.clientPrefix = "C: "
    logger.serverPrefix = "S: "
    logger.authenticationSecretDetector = StaticSecretDetector()

    let clientBytes = Array("AUTH secret\r\nPING\r\n".utf8)
    logger.logClient(clientBytes, offset: 0, count: clientBytes.count)

    let serverBytes = Array("OK\r\n".utf8)
    logger.logServer(serverBytes, offset: 0, count: serverBytes.count)

    logger.close()
    stream.close()

    let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()
    let output = String(decoding: data, as: UTF8.self)
    #expect(output.contains("C: AUTH ********"))
    #expect(output.contains("C: PING"))
    #expect(output.contains("S: OK"))
}

@Test("Smtp secret detector")
func smtpSecretDetector() {
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array("AUTH PLAIN dGVzdA==\r\n".utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    let secretBytes = buffer[secrets[0].startIndex..<(secrets[0].startIndex + secrets[0].length)]
    let secret = String(decoding: secretBytes, as: UTF8.self)
    #expect(secret == "dGVzdA==")
}

@Test("Pop3 secret detector USER/PASS")
func pop3SecretDetectorUserPass() {
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array("USER bob\r\nPASS secret\r\n".utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    let first = String(decoding: buffer[secrets[0].startIndex..<(secrets[0].startIndex + secrets[0].length)], as: UTF8.self)
    let second = String(decoding: buffer[secrets[1].startIndex..<(secrets[1].startIndex + secrets[1].length)], as: UTF8.self)
    #expect(first == "bob")
    #expect(second == "secret")
}

@Test("Imap secret detector LOGIN")
func imapSecretDetectorLogin() {
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array("A1 LOGIN bob secret\r\n".utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    let first = String(decoding: buffer[secrets[0].startIndex..<(secrets[0].startIndex + secrets[0].length)], as: UTF8.self)
    let second = String(decoding: buffer[secrets[1].startIndex..<(secrets[1].startIndex + secrets[1].length)], as: UTF8.self)
    #expect(first == "bob")
    #expect(second == "secret")
}

@Test("SMTP response parser")
func smtpResponseParser() {
    var parser = SmtpResponseParser()
    #expect(parser.parseLine("250-PIPELINING") == nil)
    let response = parser.parseLine("250 SIZE 35882577")
    #expect(response?.code == 250)
    #expect(response?.lines == ["PIPELINING", "SIZE 35882577"])
}

@Test("SMTP capabilities parsing")
func smtpCapabilitiesParsing() {
    let response = SmtpResponse(code: 250, lines: ["smtp.example.com", "SIZE 12", "STARTTLS", "AUTH PLAIN"])
    let capabilities = SmtpCapabilities.parseEhlo(response)
    #expect(capabilities?.supports("SIZE") == true)
    #expect(capabilities?.value(for: "SIZE") == "12")
    #expect(capabilities?.supports("STARTTLS") == true)
    #expect(capabilities?.value(for: "STARTTLS") == nil)
    #expect(capabilities?.supports("smtp.example.com") == false)
}

@Test("SMTP command serialization extras")
func smtpCommandSerializationExtras() {
    #expect(SmtpCommandKind.starttls.command().serialized == "STARTTLS\r\n")
    #expect(SmtpCommandKind.vrfy("user").command().serialized == "VRFY user\r\n")
    #expect(SmtpCommandKind.expn("list").command().serialized == "EXPN list\r\n")
    #expect(SmtpCommandKind.help(nil).command().serialized == "HELP\r\n")
    #expect(SmtpCommandKind.help("INFO").command().serialized == "HELP INFO\r\n")
}

@Test("POP3 response parser")
func pop3ResponseParser() {
    let ok = Pop3Response.parse("+OK ready")
    #expect(ok?.status == .ok)
    #expect(ok?.message == "ready")
    let err = Pop3Response.parse("-ERR auth failed")
    #expect(err?.status == .err)
    #expect(err?.message == "auth failed")
}

@Test("POP3 command serialization extras")
func pop3CommandSerializationExtras() {
    #expect(Pop3CommandKind.stls.command().serialized == "STLS\r\n")
    #expect(Pop3CommandKind.apop("bob", "digest").command().serialized == "APOP bob digest\r\n")
    #expect(Pop3CommandKind.auth("PLAIN", initialResponse: nil).command().serialized == "AUTH PLAIN\r\n")
    #expect(Pop3CommandKind.auth("PLAIN", initialResponse: "dGVzdA==").command().serialized == "AUTH PLAIN dGVzdA==\r\n")
}

@Test("POP3 capabilities parsing")
func pop3CapabilitiesParsing() {
    let response = Pop3Response(status: .ok, message: "capabilities")
    let event = Pop3ResponseEvent.multiline(response, ["USER", "SASL PLAIN LOGIN", "UIDL"])
    let capabilities = Pop3Capabilities.parse(event)
    #expect(capabilities?.supports("USER") == true)
    #expect(capabilities?.supports("UIDL") == true)
    #expect(capabilities?.value(for: "SASL") == "PLAIN LOGIN")
}

@Test("POP3 listing parsers")
func pop3ListingParsers() {
    let listItems = Pop3ListParser.parse(["1 10", "2 20"])
    #expect(listItems.count == 2)
    #expect(listItems.first?.size == 10)

    let uidlItems = Pop3UidlParser.parse(["1 uid1", "2 uid2"])
    #expect(uidlItems.count == 2)
    #expect(uidlItems.last?.uid == "uid2")

    let stat = Pop3StatResponse.parse(Pop3Response(status: .ok, message: "2 320"))
    #expect(stat?.count == 2)
    #expect(stat?.size == 320)
}

@Test("IMAP response parser")
func imapResponseParser() {
    let greeting = ImapResponse.parse("* OK IMAP4rev1 Service Ready")
    #expect(greeting?.kind == .untagged)
    #expect(greeting?.status == .ok)
    #expect(greeting?.text == "IMAP4rev1 Service Ready")

    let tagged = ImapResponse.parse("A1 NO LOGIN failed")
    #expect(tagged?.kind == .tagged("A1"))
    #expect(tagged?.status == .no)
    #expect(tagged?.text == "LOGIN failed")

    let continuation = ImapResponse.parse("+ Ready for literal")
    #expect(continuation?.kind == .continuation)
    #expect(continuation?.status == nil)
    #expect(continuation?.text == "Ready for literal")
}

@Test("IMAP command serialization extras")
func imapCommandSerializationExtras() {
    #expect(ImapCommandKind.create("INBOX").command(tag: "A1").serialized == "A1 CREATE INBOX\r\n")
    #expect(ImapCommandKind.list("\"\"", "*").command(tag: "A1").serialized == "A1 LIST \"\" *\r\n")
    #expect(ImapCommandKind.status("INBOX", items: ["MESSAGES", "UIDNEXT"]).command(tag: "A1").serialized == "A1 STATUS INBOX (MESSAGES UIDNEXT)\r\n")
    #expect(ImapCommandKind.uidFetch("1:*", "(FLAGS)").command(tag: "A1").serialized == "A1 UID FETCH 1:* (FLAGS)\r\n")
    #expect(ImapCommandKind.enable(["UTF8=ACCEPT"]).command(tag: "A1").serialized == "A1 ENABLE UTF8=ACCEPT\r\n")
    #expect(ImapCommandKind.starttls.command(tag: "A1").serialized == "A1 STARTTLS\r\n")
}

@Test("IMAP capabilities parsing")
func imapCapabilitiesParsing() {
    let line = "* CAPABILITY IMAP4rev1 IDLE AUTH=PLAIN"
    let capabilities = ImapCapabilities.parse(from: line)
    #expect(capabilities?.supports("IMAP4rev1") == true)
    #expect(capabilities?.supports("IDLE") == true)
    #expect(capabilities?.supports("AUTH=PLAIN") == true)

    let bracketed = "* OK [CAPABILITY IMAP4rev1 STARTTLS] Ready"
    let bracketedCaps = ImapCapabilities.parse(from: bracketed)
    #expect(bracketedCaps?.supports("STARTTLS") == true)
}

@Test("IMAP response parsers")
func imapResponseParsers() {
    let search = ImapSearchResponse.parse("* SEARCH 1 2 3")
    #expect(search?.ids == [1, 2, 3])

    let status = ImapStatusResponse.parse("* STATUS INBOX (MESSAGES 2 UIDNEXT 5)")
    #expect(status?.mailbox == "INBOX")
    #expect(status?.items["UIDNEXT"] == 5)

    let fetch = ImapFetchResponse.parse("* 1 FETCH (FLAGS (\\Seen))")
    #expect(fetch?.sequence == 1)
    #expect(fetch?.payload.contains("FLAGS") == true)

    let attributes = ImapFetchAttributes.parsePayload("(FLAGS (\\Seen \\Answered) UID 12 RFC822.SIZE 123 INTERNALDATE \"01-Jan-2020 00:00:00 +0000\")")
    #expect(attributes?.flags.contains("\\Seen") == true)
    #expect(attributes?.uid == 12)
    #expect(attributes?.size == 123)

    let full = ImapFetchAttributes.parsePayload("(FLAGS (\\Seen) UID 4 MODSEQ (123) ENVELOPE (NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL) BODYSTRUCTURE (\"TEXT\" \"PLAIN\" NIL NIL NIL \"7BIT\" 1 1))")
    #expect(full?.modSeq == 123)
    #expect(full?.envelopeRaw?.hasPrefix("(") == true)
    #expect(full?.parsedEnvelope() != nil)
    #expect(full?.bodyStructure?.contains("TEXT") == true)
}

@Test("LineBuffer incremental")
func lineBufferIncremental() {
    var buffer = LineBuffer()
    let first = buffer.append(Array("A\r".utf8))
    #expect(first.isEmpty)
    let second = buffer.append(Array("\nB\r\n".utf8))
    #expect(second == ["A", "B"])
}

@Test("SMTP response decoder incremental")
func smtpResponseDecoderIncremental() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250-PIPELINING\r\n250 SIZE 12\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.lines == ["PIPELINING", "SIZE 12"])
}

@Test("POP3 response decoder incremental")
func pop3ResponseDecoderIncremental() {
    var decoder = Pop3ResponseDecoder()
    let responses = decoder.append(Array("+OK ready\r\n-ERR bad\r\n".utf8))
    #expect(responses.count == 2)
    #expect(responses.first?.status == .ok)
    #expect(responses.last?.status == .err)
}

@Test("IMAP response decoder incremental")
func imapResponseDecoderIncremental() {
    var decoder = ImapResponseDecoder()
    let responses = decoder.append(Array("* OK hi\r\nA1 NO fail\r\n".utf8))
    #expect(responses.count == 2)
    #expect(responses.first?.status == .ok)
    #expect(responses.last?.status == .no)
}

@Test("POP3 multiline decoder")
func pop3MultilineDecoder() {
    var decoder = Pop3MultilineDecoder()
    decoder.expectMultiline()
    let bytes = Array("+OK list follows\r\n1 10\r\n2 20\r\n.\r\n".utf8)
    let events = decoder.append(bytes)
    #expect(events.count == 1)
    guard case let .multiline(response, lines) = events.first else {
        #expect(Bool(false))
        return
    }
    #expect(response.status == .ok)
    #expect(lines == ["1 10", "2 20"])
}

@Test("IMAP literal decoder")
func imapLiteralDecoder() {
    var decoder = ImapLiteralDecoder()
    let first = decoder.append(Array("* 1 FETCH {5}\r\n".utf8))
    #expect(first.isEmpty)
    let second = decoder.append(Array("HELLO".utf8))
    #expect(second.count == 1)
    #expect(second.first?.line == "* 1 FETCH {5}")
    #expect(String(decoding: second.first?.literal ?? [], as: UTF8.self) == "HELLO")
}

@Test("SMTP client send/receive pipeline")
func smtpClientPipeline() {
    let client = SmtpClient()
    let command = client.makeCommand("NOOP")
    let bytes = client.send(command)
    #expect(String(decoding: bytes, as: UTF8.self) == "NOOP\r\n")
    let responses = client.handleIncoming(Array("250 OK\r\n".utf8))
    #expect(responses.first?.code == 250)
}

@Test("SMTP DATA writer dot-stuffing")
func smtpDataWriterDotStuffing() {
    let input = Array(".hello\r\n..world\r\nend\r\n".utf8)
    let output = SmtpDataWriter.prepare(input)
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("..hello\r\n"))
    #expect(text.contains("...world\r\n"))
    #expect(text.hasSuffix("\r\n.\r\n"))
}

@Test("SMTP auth state update")
func smtpAuthStateUpdate() {
    let client = SmtpClient()
    client.connect(to: URL(string: "smtp://localhost")!)
    _ = client.send(.auth("PLAIN", initialResponse: "dGVzdA=="))
    #expect(client.state == .authenticating)
    _ = client.handleIncoming(Array("235 2.7.0 OK\r\n".utf8))
    #expect(client.state == .connected)
}

@Test("POP3 client send/receive pipeline")
func pop3ClientPipeline() {
    let client = Pop3Client()
    let command = client.makeCommand("NOOP")
    let bytes = client.send(command)
    #expect(String(decoding: bytes, as: UTF8.self) == "NOOP\r\n")
    let responses = client.handleIncoming(Array("+OK ready\r\n".utf8))
    #expect(responses.first?.status == .ok)

    client.expectMultilineResponse()
    let events = client.handleIncomingMultiline(Array("+OK list\r\n1\r\n.\r\n".utf8))
    #expect(events.count == 1)
}

@Test("POP3 auth state update")
func pop3AuthStateUpdate() {
    let client = Pop3Client()
    client.connect(to: URL(string: "pop3://localhost")!)
    _ = client.send(.user("bob"))
    #expect(client.state == .authenticating)
    _ = client.handleIncoming(Array("+OK\r\n".utf8))
    #expect(client.state == .authenticating)
    _ = client.send(.pass("secret"))
    _ = client.handleIncoming(Array("+OK\r\n".utf8))
    #expect(client.state == .authenticated)
}

@Test("IMAP client send/receive pipeline")
func imapClientPipeline() {
    let client = ImapClient()
    let command = client.makeCommand("NOOP")
    let bytes = client.send(command)
    #expect(String(decoding: bytes, as: UTF8.self).hasPrefix("A0001 NOOP"))
    let responses = client.handleIncoming(Array("* OK hi\r\n".utf8))
    #expect(responses.first?.status == .ok)
}

@Test("IMAP state and capabilities updates")
func imapStateAndCapabilitiesUpdates() {
    let client = ImapClient()
    client.connect(to: URL(string: "imap://localhost")!)

    let login = client.send(.login("user", "pass"))
    _ = client.handleIncoming(Array("\(login.tag) OK LOGIN\r\n".utf8))
    #expect(client.state == .authenticated)

    _ = client.handleIncoming(Array("* PREAUTH Ready\r\n".utf8))
    #expect(client.state == .authenticated)

    _ = client.handleIncomingWithLiterals(Array("* CAPABILITY IMAP4rev1 IDLE\r\n".utf8))
    #expect(client.capabilities?.supports("IDLE") == true)
}

@Test("Transport integration pipelines")
func transportIntegrationPipelines() {
    var clientToServerInput: InputStream?
    var clientToServerOutput: OutputStream?
    Stream.getBoundStreams(withBufferSize: 1024, inputStream: &clientToServerInput, outputStream: &clientToServerOutput)

    var serverToClientInput: InputStream?
    var serverToClientOutput: OutputStream?
    Stream.getBoundStreams(withBufferSize: 1024, inputStream: &serverToClientInput, outputStream: &serverToClientOutput)

    guard let clientToServerInput, let clientToServerOutput, let serverToClientInput, let serverToClientOutput else {
        #expect(Bool(false))
        return
    }

    let clientTransport = StreamTransport(input: serverToClientInput, output: clientToServerOutput)
    let serverTransport = StreamTransport(input: clientToServerInput, output: serverToClientOutput)

    let smtp = SmtpClient()
    smtp.connect(transport: clientTransport)
    serverTransport.open()

    let noop = smtp.makeCommand(.noop)
    _ = smtp.send(noop)

    var serverReader = StreamReader(stream: clientToServerInput)
    let received = String(decoding: serverReader.readOnce(), as: UTF8.self)
    #expect(received.contains("NOOP"))

    _ = serverTransport.write(Array("250 OK\r\n".utf8))
    let responses = smtp.receive()
    #expect(responses.first?.isSuccess == true)
}

@Test("Client states and command kinds")
func clientStatesAndCommandKinds() {
    let smtp = SmtpClient()
    #expect(smtp.state == .disconnected)
    smtp.connect(to: URL(string: "smtp://localhost")!)
    smtp.beginAuthentication()
    #expect(smtp.state == .authenticating)
    smtp.endAuthentication()
    #expect(smtp.state == .connected)

    let pop3 = Pop3Client()
    pop3.connect(to: URL(string: "pop3://localhost")!)
    pop3.beginAuthentication()
    #expect(pop3.state == .authenticating)
    pop3.endAuthentication()
    #expect(pop3.state == .authenticated)

    let imap = ImapClient()
    imap.connect(to: URL(string: "imap://localhost")!)
    imap.beginAuthentication()
    #expect(imap.state == .authenticating)
    imap.endAuthentication()
    #expect(imap.state == .authenticated)

    let smtpCmd = smtp.makeCommand(.mailFrom("user@example.com"))
    #expect(smtpCmd.serialized == "MAIL FROM:<user@example.com>\r\n")

    let popCmd = pop3.makeCommand(.uidl(nil))
    #expect(popCmd.serialized == "UIDL\r\n")

    let capaCmd = pop3.makeCommand(.capa)
    #expect(capaCmd.serialized == "CAPA\r\n")

    let imapCmd = imap.makeCommand(.capability)
    #expect(imapCmd.serialized.contains("CAPABILITY"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("AsyncStream transport integration")
func asyncStreamTransportIntegration() async throws {
    let transport = AsyncStreamTransport()
    try await transport.start()
    try await transport.send(Array("PING".utf8))
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "PING")

    await transport.yieldIncoming(Array("PONG".utf8))
    var iterator = transport.incoming.makeAsyncIterator()
    let received = await iterator.next()
    #expect(String(decoding: received ?? [], as: UTF8.self) == "PONG")

    await transport.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP continuation handling")
func asyncImapContinuationHandling() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("+ Ready\r\n".utf8))
    let continuation = await client.waitForContinuation()
    #expect(continuation?.kind == .continuation)
    #expect(continuation?.text == "Ready")

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP literal handling")
func asyncImapLiteralHandling() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* 1 FETCH {5}\r\n".utf8))
    await transport.yieldIncoming(Array("HELLO".utf8))
    let first = await client.nextMessages()
    let second = await client.nextMessages()

    #expect(first.isEmpty)
    #expect(second.count == 1)
    #expect(second.first?.line == "* 1 FETCH {5}")
    #expect(String(decoding: second.first?.literal ?? [], as: UTF8.self) == "HELLO")

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP client integration")
func asyncSmtpClientIntegration() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncSmtpClient(transport: transport)
    try await client.start()

    let command = await client.makeCommand(.noop)
    _ = try await client.send(command)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "NOOP\r\n")

    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = await client.waitForResponse()
    #expect(response?.isSuccess == true)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session flow")
func asyncSmtpSessionFlow() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    let greeting = try await connectTask.value
    #expect(greeting?.code == 220)

    let ehloTask = Task { try await session.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8))
    let capabilities = try await ehloTask.value
    #expect(capabilities?.supports("SIZE") == true)

    let dataTask = Task { try await session.sendData(Array("Hello\r\n".utf8)) }
    await transport.yieldIncoming(Array("354 End data\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await dataTask.value
    #expect(response?.code == 250)

    let sent = await transport.sentSnapshot()
    let sentText = sent.map { String(decoding: $0, as: UTF8.self) }
    #expect(sentText.contains("EHLO localhost\r\n"))
    #expect(sentText.contains("DATA\r\n"))
    let dataChunk = sentText.last ?? ""
    #expect(dataChunk.hasSuffix("\r\n.\r\n"))
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session send mail")
func asyncSmtpSessionSendMail() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let sendTask = Task {
        try await session.sendMail(from: "alice@example.com", to: ["bob@example.com"], data: Array("Hello\r\n".utf8))
    }
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    await transport.yieldIncoming(Array("354 End data\r\n".utf8))
    await transport.yieldIncoming(Array("250 OK\r\n".utf8))
    let response = try await sendTask.value
    #expect(response.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP session STARTTLS")
func asyncSmtpSessionStartTls() async throws {
    let transport = StartTlsAsyncTransport()
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("220 Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: false) }
    await transport.yieldIncoming(Array("220 Go ahead\r\n".utf8))
    let response = try await startTlsTask.value
    #expect(response.code == 220)
    #expect(await transport.didStartTls() == true)
    #expect(await transport.lastStartTlsValidation() == false)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "STARTTLS\r\n")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP capabilities")
func asyncSmtpCapabilities() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncSmtpClient(transport: transport)
    try await client.start()

    let task = Task { try await client.ehlo(domain: "localhost") }
    await transport.yieldIncoming(Array("250-smtp.example.com\r\n250-SIZE 12\r\n250 STARTTLS\r\n".utf8))
    let capabilities = try await task.value
    #expect(capabilities?.supports("STARTTLS") == true)
    #expect(capabilities?.value(for: "SIZE") == "12")
    #expect(await client.capabilities?.supports("STARTTLS") == true)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async SMTP auth state updates")
func asyncSmtpAuthStateUpdates() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncSmtpClient(transport: transport)
    try await client.start()

    await client.beginAuthentication()
    await client.handleAuthenticationResponse(SmtpResponse(code: 235, lines: ["2.7.0 ok"]))
    #expect(await client.state == .connected)

    await client.beginAuthentication()
    await client.handleAuthenticationResponse(SmtpResponse(code: 535, lines: ["5.7.8 bad"]))
    #expect(await client.state == .connected)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 client integration")
func asyncPop3ClientIntegration() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncPop3Client(transport: transport)
    try await client.start()

    let command = await client.makeCommand(.stat)
    _ = try await client.send(command)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "STAT\r\n")

    await transport.yieldIncoming(Array("+OK 1 10\r\n".utf8))
    let responses = await client.nextResponses()
    #expect(responses.first?.isSuccess == true)

    await client.expectMultilineResponse()
    await transport.yieldIncoming(Array("+OK list\r\n1\r\n.\r\n".utf8))
    let events = await client.nextEvents()
    #expect(events.count == 1)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session flow")
func asyncPop3SessionFlow() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    let greeting = try await connectTask.value
    #expect(greeting?.isSuccess == true)

    let capaTask = Task { try await session.capability() }
    await transport.yieldIncoming(Array("+OK\r\nUSER\r\n.\r\n".utf8))
    let caps = try await capaTask.value
    #expect(caps?.supports("USER") == true)

    let authTask = Task { try await session.authenticate(user: "bob", password: "secret") }
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    await transport.yieldIncoming(Array("+OK\r\n".utf8))
    let result = try await authTask.value
    #expect(result.pass?.isSuccess == true)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session STARTTLS")
func asyncPop3SessionStartTls() async throws {
    let transport = StartTlsAsyncTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    await transport.yieldIncoming(Array("+OK Begin TLS\r\n".utf8))
    let response = try await startTlsTask.value
    #expect(response.isSuccess == true)
    #expect(await transport.didStartTls() == true)
    #expect(await transport.lastStartTlsValidation() == true)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "STLS\r\n")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 session listings")
func asyncPop3SessionListings() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncPop3Session(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("+OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let statTask = Task { try await session.stat() }
    await transport.yieldIncoming(Array("+OK 2 320\r\n".utf8))
    let stat = try await statTask.value
    #expect(stat.count == 2)

    let listTask = Task { try await session.list() }
    await transport.yieldIncoming(Array("+OK\r\n1 10\r\n.\r\n".utf8))
    let list = try await listTask.value
    #expect(list.count == 1)

    let uidlTask = Task { try await session.uidl() }
    await transport.yieldIncoming(Array("+OK\r\n1 uid1\r\n.\r\n".utf8))
    let uidl = try await uidlTask.value
    #expect(uidl.first?.uid == "uid1")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 CAPA parsing")
func asyncPop3CapaParsing() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncPop3Client(transport: transport)
    try await client.start()

    let task = Task { try await client.capa() }
    await transport.yieldIncoming(Array("+OK\r\nUSER\r\nSASL PLAIN\r\n.\r\n".utf8))
    let capabilities = try await task.value
    #expect(capabilities?.supports("USER") == true)
    #expect(capabilities?.value(for: "SASL") == "PLAIN")
    #expect(await client.capabilities?.supports("USER") == true)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async POP3 auth state updates")
func asyncPop3AuthStateUpdates() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncPop3Client(transport: transport)
    try await client.start()

    await client.beginAuthentication()
    await client.handleAuthenticationResponse(Pop3Response(status: .ok, message: "ok"))
    #expect(await client.state == .authenticated)
    await client.stop()

    let errorTransport = AsyncStreamTransport()
    let errorClient = AsyncPop3Client(transport: errorTransport)
    try await errorClient.start()
    await errorClient.beginAuthentication()
    await errorClient.handleAuthenticationResponse(Pop3Response(status: .err, message: "bad"))
    #expect(await errorClient.state == .connected)
    await errorClient.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP flow helpers")
func asyncImapFlowHelpers() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    let capTask = Task { try await client.capability() }
    await transport.yieldIncoming(Array("A0001 OK CAPABILITY\r\n".utf8))
    let capResponse = try await capTask.value
    #expect(capResponse?.status == .ok)

    let loginTask = Task { try await client.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0002 OK LOGIN\r\n".utf8))
    let loginResponse = try await loginTask.value
    #expect(loginResponse?.status == .ok)
    #expect(await client.state == .authenticated)

    let selectTask = Task { try await client.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("A0003 OK SELECT\r\n".utf8))
    let selectResponse = try await selectTask.value
    #expect(selectResponse?.status == .ok)
    #expect(await client.state == .selected)

    await client.stop()
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session flow")
func asyncImapSessionFlow() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    let greeting = try await connectTask.value
    #expect(greeting?.status == .ok)

    let capabilityTask = Task { try await session.capability() }
    await transport.yieldIncoming(Array("A0001 OK CAPABILITY\r\n".utf8))
    let capability = try await capabilityTask.value
    #expect(capability?.status == .ok)

    let loginTask = Task { try await session.login(user: "user", password: "pass") }
    await transport.yieldIncoming(Array("A0002 OK LOGIN\r\n".utf8))
    let login = try await loginTask.value
    #expect(login?.status == .ok)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session STARTTLS")
func asyncImapSessionStartTls() async throws {
    let transport = StartTlsAsyncTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    await transport.yieldIncoming(Array("A0001 OK Begin TLS\r\n".utf8))
    let response = try await startTlsTask.value
    #expect(response.isOk == true)
    #expect(await transport.didStartTls() == true)
    #expect(await transport.lastStartTlsValidation() == true)
    let sent = await transport.sentSnapshot()
    #expect(String(decoding: sent.first ?? [], as: UTF8.self) == "A0001 STARTTLS\r\n")
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session queries")
func asyncImapSessionQueries() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let searchTask = Task { try await session.search("ALL") }
    await transport.yieldIncoming(Array("* SEARCH 1 2 3\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK SEARCH\r\n".utf8))
    let search = try await searchTask.value
    #expect(search.ids == [1, 2, 3])

    let statusTask = Task { try await session.status(mailbox: "INBOX", items: ["MESSAGES", "UIDNEXT"]) }
    await transport.yieldIncoming(Array("* STATUS INBOX (MESSAGES 2 UIDNEXT 5)\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK STATUS\r\n".utf8))
    let status = try await statusTask.value
    #expect(status.items["UIDNEXT"] == 5)

    let fetchTask = Task { try await session.fetch("1", items: "FLAGS") }
    await transport.yieldIncoming(Array("* 1 FETCH (FLAGS (\\Seen))\r\n".utf8))
    await transport.yieldIncoming(Array("A0003 OK FETCH\r\n".utf8))
    let fetch = try await fetchTask.value
    #expect(fetch.count == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session selected state and QRESYNC fetch")
func asyncImapSessionSelectedStateQresync() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* 3 EXISTS\r\n".utf8))
    await transport.yieldIncoming(Array("* 1 RECENT\r\n".utf8))
    await transport.yieldIncoming(Array("* OK [UIDVALIDITY 7] Ready\r\n".utf8))
    await transport.yieldIncoming(Array("* OK [UIDNEXT 10] Next\r\n".utf8))
    await transport.yieldIncoming(Array("* OK [HIGHESTMODSEQ 55] Modseq\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK SELECT\r\n".utf8))
    _ = try await selectTask.value

    #expect(await session.selectedMailbox == "INBOX")
    let selected = await session.selectedState
    #expect(selected.uidValidity == 7)
    #expect(selected.uidNext == 10)
    #expect(selected.highestModSeq == 55)
    #expect(selected.messageCount == 3)
    #expect(selected.recentCount == 1)

    let fetchTask = Task { try await session.fetchWithQresync("1", items: "UID MODSEQ") }
    await transport.yieldIncoming(Array("* 1 FETCH (UID 100 MODSEQ (57))\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 EXPUNGE\r\n".utf8))
    await transport.yieldIncoming(Array("* VANISHED 101:102\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK FETCH\r\n".utf8))
    let result = try await fetchTask.value
    #expect(result.responses.count == 1)
    #expect(result.qresyncEvents.count == 2)
    let updated = await session.selectedState
    #expect(updated.highestModSeq == 57)
    #expect(updated.messageCount == 2)
    #expect(updated.lastExpungeSequence == 2)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session BODY fetch maps with QRESYNC")
func asyncImapSessionBodyFetchMapsQresync() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let fetchTask = Task { try await session.fetchBodySectionsWithQresync("1", items: "BODY[]") }
    await transport.yieldIncoming(Array("* 1 FETCH (BODY[] {5}\r\n".utf8))
    await transport.yieldIncoming(Array("Hello".utf8))
    await transport.yieldIncoming(Array("* VANISHED 2\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK FETCH\r\n".utf8))
    let result = try await fetchTask.value
    #expect(result.bodies.count == 1)
    #expect(result.bodies.first?.body() == Array("Hello".utf8))
    #expect(result.qresyncEvents.count == 1)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP session UID fetch mapping")
func asyncImapSessionUidFetchMapping() async throws {
    let transport = AsyncStreamTransport()
    let session = AsyncImapSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
    _ = try await connectTask.value

    let selectTask = Task { try await session.select(mailbox: "INBOX") }
    await transport.yieldIncoming(Array("* OK [UIDVALIDITY 7] Ready\r\n".utf8))
    await transport.yieldIncoming(Array("A0001 OK SELECT\r\n".utf8))
    _ = try await selectTask.value

    let uidSet = UniqueIdSet([UniqueId(validity: 7, id: 100), UniqueId(validity: 7, id: 200)])
    let fetchTask = Task { try await session.uidFetchWithQresync(uidSet, items: "UID MODSEQ") }
    await transport.yieldIncoming(Array("* 1 FETCH (UID 100 MODSEQ (56))\r\n".utf8))
    await transport.yieldIncoming(Array("* 2 FETCH (UID 200 MODSEQ (57))\r\n".utf8))
    await transport.yieldIncoming(Array("A0002 OK UID FETCH\r\n".utf8))
    _ = try await fetchTask.value

    let state = await session.selectedState
    #expect(state.uidBySequence[1]?.id == 100)
    #expect(state.uidBySequence[2]?.id == 200)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async transport factory async-stream backend")
func asyncTransportFactoryAsyncStream() throws {
    let transport = try AsyncTransportFactory.make(host: "localhost", port: 1, backend: .asyncStream)
    #expect(transport is AsyncStreamTransport)
}

#if canImport(Network)
@available(macOS 10.15, iOS 13.0, *)
@Test("Network transport async STARTTLS support")
func networkTransportStartTlsSupport() throws {
    let transport = try AsyncTransportFactory.make(host: "localhost", port: 1, backend: .network)
    #expect(transport is AsyncStartTlsTransport)
}
#endif

@Test("Sync transport factory TCP backend")
func transportFactoryTcp() throws {
    let transport = try TransportFactory.make(host: "localhost", port: 1, backend: .tcp)
    #expect(transport is TcpTransport)
}

#if !os(iOS)
@Test("Sync transport factory socket backend")
func transportFactorySocket() throws {
    let transport = try TransportFactory.make(host: "localhost", port: 1, backend: .socket)
    #expect(transport is PosixSocketTransport)
}
#endif

@Test("Sync SMTP session flow")
func syncSmtpSessionFlow() throws {
    let transport = TestTransport(incoming: [
        Array("220 Ready\r\n".utf8),
        Array("250-smtp.example.com\r\n250 SIZE 12\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("250 OK\r\n".utf8),
        Array("354 End data\r\n".utf8),
        Array("250 OK\r\n".utf8)
    ])
    let session = SmtpSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    _ = try session.ehlo(domain: "localhost")
    _ = try session.sendMail(from: "alice@example.com", to: ["bob@example.com"], data: Array("Hello\r\n".utf8))
    let sent = transport.written.map { String(decoding: $0, as: UTF8.self) }
    #expect(sent.contains("EHLO localhost\r\n"))
    #expect(sent.contains("MAIL FROM:<alice@example.com>\r\n"))
}

@Test("Sync SMTP session write failure")
func syncSmtpSessionWriteFailure() throws {
    let transport = FailingTransport(incoming: [Array("220 Ready\r\n".utf8)])
    let session = SmtpSession(transport: transport, maxReads: 1)
    _ = try session.connect()
    #expect(throws: SessionError.transportWriteFailed) {
        _ = try session.helo(domain: "localhost")
    }
}

@Test("StartTLS unsupported")
func startTlsUnsupported() throws {
    let transport = TestTransport(incoming: [Array("220 Ready\r\n".utf8), Array("220 Go ahead\r\n".utf8)])
    let session = SmtpSession(transport: transport, maxReads: 1)
    _ = try session.connect()
    #expect(throws: SessionError.startTlsNotSupported) {
        _ = try session.startTls()
    }
}

@Test("StartTLS supported")
func startTlsSupported() throws {
    let transport = StartTlsTestTransport(incoming: [Array("220 Ready\r\n".utf8), Array("220 Go ahead\r\n".utf8)])
    let session = SmtpSession(transport: transport, maxReads: 2)
    _ = try session.connect()
    let response = try session.startTls()
    #expect(response.code == 220)
    #expect(transport.didStartTls == true)
}

@Test("Sync POP3 session flow")
func syncPop3SessionFlow() throws {
    let transport = TestTransport(incoming: [
        Array("+OK Ready\r\n".utf8),
        Array("+OK\r\nUSER\r\n.\r\n".utf8),
        Array("+OK 2 320\r\n".utf8)
    ])
    let session = Pop3Session(transport: transport, maxReads: 3)
    _ = try session.connect()
    let caps = try session.capability()
    #expect(caps.supports("USER") == true)
    let stat = try session.stat()
    #expect(stat.count == 2)
}

@Test("Sync IMAP session flow")
func syncImapSessionFlow() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("* SEARCH 1 2 3\r\n".utf8),
        Array("A0001 OK SEARCH\r\n".utf8),
        Array("* STATUS INBOX (MESSAGES 2 UIDNEXT 5)\r\n".utf8),
        Array("A0002 OK STATUS\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 3)
    _ = try session.connect()
    let search = try session.search("ALL")
    #expect(search.ids == [1, 2, 3])
    let status = try session.status(mailbox: "INBOX", items: ["MESSAGES", "UIDNEXT"])
    #expect(status.items["MESSAGES"] == 2)
}

@Test("Sync IMAP session selected state and QRESYNC fetch")
func syncImapSessionSelectedStateQresync() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("* 3 EXISTS\r\n".utf8),
        Array("* 1 RECENT\r\n".utf8),
        Array("* OK [UIDVALIDITY 7] Ready\r\n".utf8),
        Array("* OK [UIDNEXT 10] Next\r\n".utf8),
        Array("* OK [HIGHESTMODSEQ 55] Modseq\r\n".utf8),
        Array("A0001 OK SELECT\r\n".utf8),
        Array("* 1 FETCH (UID 100 MODSEQ (57))\r\n".utf8),
        Array("* 2 EXPUNGE\r\n".utf8),
        Array("* VANISHED 101:102\r\n".utf8),
        Array("A0002 OK FETCH\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 6)
    _ = try session.connect()
    _ = try session.select(mailbox: "INBOX")
    #expect(session.selectedMailbox == "INBOX")
    #expect(session.selectedState.uidValidity == 7)
    #expect(session.selectedState.uidNext == 10)
    #expect(session.selectedState.highestModSeq == 55)
    #expect(session.selectedState.messageCount == 3)
    #expect(session.selectedState.recentCount == 1)

    let result = try session.fetchWithQresync("1", items: "UID MODSEQ")
    #expect(result.responses.count == 1)
    #expect(result.qresyncEvents.count == 2)
    #expect(session.selectedState.highestModSeq == 57)
    #expect(session.selectedState.messageCount == 2)
    #expect(session.selectedState.lastExpungeSequence == 2)
}

@Test("Sync IMAP session BODY fetch maps with QRESYNC")
func syncImapSessionBodyFetchMapsQresync() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("* 1 FETCH (BODY[] {5}\r\n".utf8),
        Array("Hello".utf8),
        Array("* VANISHED 2\r\n".utf8),
        Array("A0001 OK FETCH\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 4)
    _ = try session.connect()
    let result = try session.fetchBodySectionsWithQresync("1", items: "BODY[]")
    #expect(result.bodies.count == 1)
    #expect(result.bodies.first?.body() == Array("Hello".utf8))
    #expect(result.qresyncEvents.count == 1)
}

@Test("Sync IMAP UID fetch/store mapping updates")
func syncImapSessionUidFetchStoreMapping() throws {
    let transport = TestTransport(incoming: [
        Array("* OK Ready\r\n".utf8),
        Array("* 2 EXISTS\r\n".utf8),
        Array("* OK [UIDVALIDITY 7] Ready\r\n".utf8),
        Array("A0001 OK SELECT\r\n".utf8),
        Array("* 1 FETCH (UID 100 MODSEQ (56))\r\n".utf8),
        Array("* 2 FETCH (UID 200 MODSEQ (57))\r\n".utf8),
        Array("A0002 OK UID FETCH\r\n".utf8),
        Array("* 1 EXPUNGE\r\n".utf8),
        Array("* 1 FETCH (UID 200 MODSEQ (58) FLAGS (\\Seen))\r\n".utf8),
        Array("A0003 OK UID STORE\r\n".utf8)
    ])
    let session = ImapSession(transport: transport, maxReads: 10)
    _ = try session.connect()
    _ = try session.select(mailbox: "INBOX")

    let uidSet = UniqueIdSet([UniqueId(validity: 7, id: 100), UniqueId(validity: 7, id: 200)])
    let fetchResult = try session.uidFetchWithQresync(uidSet, items: "UID MODSEQ")
    #expect(fetchResult.responses.count == 2)
    #expect(session.selectedState.uidBySequence[1]?.id == 100)
    #expect(session.selectedState.uidBySequence[2]?.id == 200)
    #expect(session.selectedState.messageCount == 2)

    let storeResult = try session.uidStoreWithQresync(uidSet, data: "+FLAGS (\\Seen)")
    #expect(storeResult.responses.count == 1)
    #expect(session.selectedState.messageCount == 1)
    #expect(session.selectedState.uidBySequence[1]?.id == 200)
    let uid200 = UniqueId(validity: 7, id: 200)
    #expect(session.selectedState.sequenceByUid[uid200] == 1)
}

class TestTransport: Transport {
    var incoming: [[UInt8]]
    var written: [[UInt8]] = []

    init(incoming: [[UInt8]] = []) {
        self.incoming = incoming
    }

    func open() {}
    func close() {}

    func write(_ bytes: [UInt8]) -> Int {
        written.append(bytes)
        return bytes.count
    }

    func readAvailable(maxLength: Int) -> [UInt8] {
        guard !incoming.isEmpty else { return [] }
        return incoming.removeFirst()
    }
}

final class FailingTransport: TestTransport {
    override func write(_ bytes: [UInt8]) -> Int {
        written.append(bytes)
        return 0
    }
}

final class StartTlsTestTransport: TestTransport, StartTlsTransport {
    private(set) var didStartTls = false

    func startTLS(validateCertificate: Bool) {
        didStartTls = true
    }
}

@available(macOS 10.15, iOS 13.0, *)
actor StartTlsAsyncTransport: AsyncStartTlsTransport {
    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var started = false
    private var sent: [[UInt8]] = []
    private var startTlsValidations: [Bool] = []

    init() {
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.incoming = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    func start() async throws {
        started = true
    }

    func stop() async {
        started = false
        continuation.finish()
    }

    func send(_ bytes: [UInt8]) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        sent.append(bytes)
    }

    func startTLS(validateCertificate: Bool) async throws {
        guard started else {
            throw AsyncTransportError.notStarted
        }
        startTlsValidations.append(validateCertificate)
    }

    func yieldIncoming(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    func sentSnapshot() -> [[UInt8]] {
        sent
    }

    func didStartTls() -> Bool {
        !startTlsValidations.isEmpty
    }

    func lastStartTlsValidation() -> Bool? {
        startTlsValidations.last
    }
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Async IMAP capability parsing")
func asyncImapCapabilityParsing() async throws {
    let transport = AsyncStreamTransport()
    let client = AsyncImapClient(transport: transport)
    try await client.start()

    await transport.yieldIncoming(Array("* CAPABILITY IMAP4rev1 IDLE\r\n".utf8))
    _ = await client.nextMessages()
    #expect(await client.capabilities?.supports("IDLE") == true)

    await client.stop()
}

#if !os(iOS)
@available(macOS 10.15, *)
@Test("Socket transport optional integration")
func socketTransportOptionalIntegration() async throws {
    let host = ProcessInfo.processInfo.environment["MAILFOUNDATION_SOCKET_TEST_HOST"]
    let portValue = ProcessInfo.processInfo.environment["MAILFOUNDATION_SOCKET_TEST_PORT"]
    guard let host, let portValue, let port = UInt16(portValue) else {
        #expect(Bool(true))
        return
    }

    let transport = SocketTransport(host: host, port: port)
    try await transport.start()
    defer { Task { await transport.stop() } }

    try await transport.send(Array("NOOP\r\n".utf8))
    var iterator = transport.incoming.makeAsyncIterator()
    _ = await iterator.next()
    #expect(Bool(true))
}
#endif
