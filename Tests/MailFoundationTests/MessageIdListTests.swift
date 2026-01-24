import Testing
@testable import MailFoundation

@Test("MessageIdList parses space-delimited IDs")
func messageIdListParsesSpaceDelimited() {
    let value = "id1@example.com id2@example.com"
    let list = MessageIdList.parse(value)
    #expect(list?.ids == ["id1@example.com", "id2@example.com"])
}

@Test("MessageIdList ignores comments")
func messageIdListIgnoresComments() {
    let value = "(foo) id1@example.com (bar)"
    let list = MessageIdList.parse(value)
    #expect(list?.ids == ["id1@example.com"])
}

@Test("MessageIdList parses comma-delimited IDs")
func messageIdListParsesCommaDelimited() {
    let value = "id1@example.com, id2@example.com"
    let list = MessageIdList.parse(value)
    #expect(list?.ids == ["id1@example.com", "id2@example.com"])
}
