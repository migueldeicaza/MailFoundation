import Testing
@testable import MailFoundation

@Test("IMAP sort command helpers")
func imapSortCommandHelpers() throws {
    let command = try ImapCommandKind.sort(.all, orderBy: [.arrival, .reverseDate]).command(tag: "A0001")
    #expect(command.serialized == "A0001 SORT (ARRIVAL REVERSE DATE) UTF-8 ALL\r\n")

    let uidCommand = try ImapCommandKind.uidSort(.all, orderBy: [.subject]).command(tag: "A0002")
    #expect(uidCommand.serialized == "A0002 UID SORT (SUBJECT) UTF-8 ALL\r\n")
}

@Test("IMAP search parser accepts SORT responses")
func imapSortResponseParsing() {
    let response = ImapSearchResponse.parse("* SORT 3 1 2")
    #expect(response?.ids == [3, 1, 2])
}

@Test("IMAP sort rejects unsupported order-by")
func imapSortRejectsUnsupportedOrderBy() {
    #expect(throws: ImapSortError.unsupportedOrderByType(.modSeq)) {
        let rule = try OrderBy(type: .modSeq, order: .ascending)
        _ = try ImapSort.buildOrderBy([rule])
    }
}

@Test("IMAP sort capability gating")
func imapSortCapabilityGating() throws {
    let noSort = ImapCapabilities(tokens: ["IMAP4rev1"])
    #expect(throws: ImapSortError.sortNotSupported) {
        try ImapSort.validateCapabilities(orderBy: [.arrival], capabilities: noSort)
    }

    let sortOnly = ImapCapabilities(tokens: ["IMAP4rev1", "SORT"])
    #expect(throws: ImapSortError.sortDisplayNotSupported) {
        try ImapSort.validateCapabilities(orderBy: [.displayFrom], capabilities: sortOnly)
    }

    #expect(throws: ImapSortError.annotationNotSupported) {
        let annotation = try OrderBy.annotation(entry: "/shared/vendor", attribute: "value.shared", order: .ascending)
        try ImapSort.validateCapabilities(orderBy: [annotation], capabilities: sortOnly)
    }

    let sortDisplay = ImapCapabilities(tokens: ["IMAP4rev1", "SORT", "SORT=DISPLAY"])
    try ImapSort.validateCapabilities(orderBy: [.displayTo], capabilities: sortDisplay)
}
