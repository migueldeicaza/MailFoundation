import Testing
@testable import MailFoundation

@Test("POP3 multiline decoder handles split terminator")
func pop3MultilineDecoderSplitTerminator() {
    var decoder = Pop3MultilineDecoder()
    decoder.expectMultiline()

    let first = Array("+OK data\r\nline\r\n.".utf8)
    let second = Array("\r\n".utf8)

    _ = decoder.append(first)
    let events = decoder.append(second)

    #expect(events.count == 1)
    guard case let .multiline(response, lines) = events.first else {
        #expect(Bool(false))
        return
    }
    #expect(response.status == .ok)
    #expect(lines == ["line"])
}

@Test("POP3 multiline decoder handles -ERR after expectMultiline")
func pop3MultilineDecoderErrResponse() {
    var decoder = Pop3MultilineDecoder()
    decoder.expectMultiline()

    let events = decoder.append(Array("-ERR nope\r\n".utf8))
    #expect(events.count == 1)
    guard case let .single(response) = events.first else {
        #expect(Bool(false))
        return
    }
    #expect(response.status == .err)
    #expect(response.message == "nope")
}
