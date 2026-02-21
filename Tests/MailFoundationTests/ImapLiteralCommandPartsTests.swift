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

@Test("IMAP literal command parser ignores literal markers inside quoted text")
func imapLiteralCommandPartsIgnoresQuotedLiteralMarkers() {
    let serialized = Array("A0001 XTEST \"fake {3}\r\nabc text\"\r\n".utf8)
    let parsed = ImapLiteralCommandParts.parse(serialized)
    #expect(parsed == nil)
}

@Test("IMAP literal command parser still parses real literal markers")
func imapLiteralCommandPartsParsesRealLiteralMarkers() {
    let serialized = Array("A0001 LOGIN {4+}\r\nuser secret\r\n".utf8)
    guard let parsed = ImapLiteralCommandParts.parse(serialized) else {
        #expect(Bool(false), "Expected literal parser result")
        return
    }

    #expect(parsed.parts.count == 1)
    #expect(String(decoding: parsed.parts[0].leading, as: UTF8.self) == "A0001 LOGIN ")
    #expect(parsed.parts[0].length == 4)
    #expect(String(decoding: parsed.parts[0].literal, as: UTF8.self) == "user")
    #expect(String(decoding: parsed.tail, as: UTF8.self) == " secret\r\n")
}
