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

@Test("SMTP response decoder drops mixed reply code continuations")
func smtpResponseDecoderMixedReplyCodes() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250-PIPELINING\r\n251 HELP\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.code == 251)
    #expect(responses.first?.lines == ["HELP"])
}

@Test("SMTP response decoder drops pending multiline on malformed line")
func smtpResponseDecoderSkipsMalformedLines() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250-PIPELINING\r\n25X bad\r\n250 OK\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.code == 250)
    #expect(responses.first?.lines == ["OK"])
}

@Test("SMTP response decoder resets pending on malformed short line")
func smtpResponseDecoderMalformedShortLine() {
    var decoder = SmtpResponseDecoder()
    let bytes = Array("250-PIPELINING\r\nBAD\r\n250 OK\r\n".utf8)
    let responses = decoder.append(bytes)
    #expect(responses.count == 1)
    #expect(responses.first?.code == 250)
    #expect(responses.first?.lines == ["OK"])
}
