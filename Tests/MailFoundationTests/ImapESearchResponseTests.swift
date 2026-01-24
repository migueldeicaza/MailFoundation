import Testing
@testable import MailFoundation

@Test("IMAP ESEARCH parses ALL with UID")
func imapESearchParsesAll() {
    let response = ImapESearchResponse.parse("* ESEARCH UID ALL 1:3")
    #expect(response?.isUid == true)
    #expect(response?.ids == [1, 2, 3])
}

@Test("IMAP ESEARCH parses COUNT and ranges")
func imapESearchParsesCount() {
    let response = ImapESearchResponse.parse("* ESEARCH (TAG \"A1\") ALL 2,4:5 COUNT 3")
    #expect(response?.isUid == false)
    #expect(response?.ids == [2, 4, 5])
    #expect(response?.count == 3)
}

@Test("IMAP ESEARCH parses MIN/MAX")
func imapESearchParsesMinMax() {
    let response = ImapESearchResponse.parse("* ESEARCH MIN 2 MAX 9")
    #expect(response?.min == 2)
    #expect(response?.max == 9)
}
