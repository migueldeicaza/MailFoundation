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

//
// ImapLiteralCommandParts.swift
//
// IMAP serialized-command literal parsing helpers.
//

import Foundation

struct ImapSerializedLiteralPart: Sendable {
    let leading: [UInt8]
    let length: Int
    let literal: [UInt8]
}

enum ImapLiteralCommandParts {
    static func parse(_ bytes: [UInt8]) -> (parts: [ImapSerializedLiteralPart], tail: [UInt8])? {
        var parts: [ImapSerializedLiteralPart] = []
        var cursor = 0
        var segmentStart = 0
        var foundLiteral = false

        while cursor < bytes.count {
            guard let markerStart = findByte(0x7B, in: bytes, from: cursor) else { break } // {
            var index = markerStart + 1
            var length = 0
            var foundDigit = false

            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                foundDigit = true
                length = (length * 10) + Int(bytes[index] - 0x30)
                index += 1
            }

            guard foundDigit else {
                cursor = markerStart + 1
                continue
            }

            if index < bytes.count, bytes[index] == 0x2B { // +
                index += 1
            }

            guard index + 2 < bytes.count,
                  bytes[index] == 0x7D,      // }
                  bytes[index + 1] == 0x0D,  // \r
                  bytes[index + 2] == 0x0A   // \n
            else {
                cursor = markerStart + 1
                continue
            }

            let literalStart = index + 3
            let literalEnd = literalStart + length
            guard literalEnd <= bytes.count else { break }

            foundLiteral = true

            let leading = Array(bytes[segmentStart..<markerStart])
            let literal = Array(bytes[literalStart..<literalEnd])
            parts.append(ImapSerializedLiteralPart(leading: leading, length: length, literal: literal))

            cursor = literalEnd
            segmentStart = literalEnd
        }

        guard foundLiteral else { return nil }
        let tail = Array(bytes[segmentStart..<bytes.count])
        return (parts, tail)
    }

    private static func findByte(_ value: UInt8, in bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        var index = start
        while index < bytes.count {
            if bytes[index] == value {
                return index
            }
            index += 1
        }
        return nil
    }
}
