//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Testing
@testable import MailFoundation

@Test("IMAP response decoder handles split CRLF")
func imapResponseDecoderHandlesSplitCrLf() {
    var decoder = ImapResponseDecoder()
    let first = decoder.append(Array("* OK hi\r".utf8))
    #expect(first.isEmpty)

    let second = decoder.append(Array("\nA1 OK done\r\n".utf8))
    #expect(second.count == 2)
    #expect(second.first?.status == .ok)
    #expect(second.last?.status == .ok)
}

@Test("IMAP literal decoder handles multiple messages per chunk")
func imapLiteralDecoderHandlesMultipleMessages() {
    var decoder = ImapLiteralDecoder()
    let bytes = Array("* 1 FETCH (BODY[] {5}\r\nHELLO)\r\n* 2 FETCH (FLAGS (\\Seen))\r\n".utf8)
    let messages = decoder.append(bytes)

    #expect(messages.count == 2)
    #expect(messages.first?.literal == Array("HELLO".utf8))
    #expect(messages.last?.line.hasPrefix("* 2 FETCH") == true)
}

@Test("IMAP literal decoder handles split literal markers")
func imapLiteralDecoderHandlesSplitLiteralMarkers() {
    var decoder = ImapLiteralDecoder()
    let part1 = Array("* 1 FETCH (BODY[] {4}\r".utf8)
    #expect(decoder.append(part1).isEmpty == true)

    let part2 = Array("\nABCD)\r\n".utf8)
    let messages = decoder.append(part2)
    #expect(messages.count == 1)
    #expect(messages.first?.literal == Array("ABCD".utf8))
}

@Test("IMAP literal decoder handles zero-length literals")
func imapLiteralDecoderHandlesZeroLengthLiterals() {
    var decoder = ImapLiteralDecoder()
    let bytes = Array("* 1 FETCH (BODY[] {0}\r\n)\r\n".utf8)
    let messages = decoder.append(bytes)

    #expect(messages.count == 1)
    #expect(messages.first?.literal?.isEmpty == true)
}
