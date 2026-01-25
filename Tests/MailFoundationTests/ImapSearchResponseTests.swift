import Testing
@testable import MailFoundation

@Test("IMAP search response captures ESEARCH metadata")
func imapSearchResponseFromESearch() {
    let esearch = ImapESearchResponse(ids: [2, 4, 6], count: 3, min: 2, max: 6, isUid: true)
    let response = ImapSearchResponse(esearch: esearch)

    #expect(response.ids == [2, 4, 6])
    #expect(response.count == 3)
    #expect(response.min == 2)
    #expect(response.max == 6)
    #expect(response.isUid == true)
}

@Test("IMAP search response can default to UID results")
func imapSearchResponseDefaultUid() {
    let esearch = ImapESearchResponse(ids: [1], count: 1, min: 1, max: 1, isUid: false)
    let response = ImapSearchResponse(esearch: esearch, defaultIsUid: true)

    #expect(response.isUid == true)
}

@Test("IMAP search response parses SEARCH without metadata")
func imapSearchResponseParsesSearch() {
    let response = ImapSearchResponse.parse("* SEARCH 5 7 9")

    #expect(response?.ids == [5, 7, 9])
    #expect(response?.count == nil)
    #expect(response?.min == nil)
    #expect(response?.max == nil)
    #expect(response?.isUid == false)
}

@Test("IMAP search response idSet uses isUid to choose set type")
func imapSearchResponseIdSetUsesUid() {
    let search = ImapSearchResponse(ids: [1, 2, 3], isUid: false)
    switch search.idSet() {
    case let .sequence(set):
        #expect(Array(set) == [1, 2, 3])
    case .uid:
        #expect(Bool(false))
    }

    let uidSearch = ImapSearchResponse(ids: [4, 5], isUid: true)
    switch uidSearch.idSet(validity: 7) {
    case .sequence:
        #expect(Bool(false))
    case let .uid(set):
        #expect(set.validity == 7)
        #expect(set.count == 2)
    }
}
