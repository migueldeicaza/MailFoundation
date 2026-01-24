import Testing
@testable import MailFoundation

@Test("SMTP response decoder handles empty multiline segments")
func smtpResponseDecoderEmptySegments() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250-\r\n250 OK\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.lines == ["", "OK"])
}

@Test("SMTP response decoder handles split replies across chunks")
func smtpResponseDecoderSplitChunks() {
    var decoder = SmtpResponseDecoder()
    let first = decoder.append(Array("250-PIPELIN".utf8))
    #expect(first.isEmpty)
    let second = decoder.append(Array("ING\r\n250 OK\r\n".utf8))
    #expect(second.count == 1)
    #expect(second.first?.lines == ["PIPELINING", "OK"])
}

@Test("SMTP response decoder preserves leading spaces in lines")
func smtpResponseDecoderLeadingSpaces() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250- \r\n250  OK\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.lines == [" ", " OK"])
}
