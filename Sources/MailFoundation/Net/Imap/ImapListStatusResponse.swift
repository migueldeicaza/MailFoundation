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
// ImapListStatusResponse.swift
//
// IMAP LIST-STATUS response parsing.
//

import Foundation

public struct ImapListStatusResponse: Sendable, Equatable {
    public let mailbox: ImapMailbox
    public let statusItems: [String: Int]

    public static func parse(_ line: String) -> ImapListStatusResponse? {
        parse(line, literals: [])
    }

    /// Parses a LIST-STATUS response from a literal-aware message.
    ///
    /// - Parameter message: The literal response message.
    /// - Returns: The parsed list status response, or `nil` if parsing fails.
    public static func parse(_ message: ImapLiteralMessage) -> ImapListStatusResponse? {
        parse(message.line, literals: message.literals)
    }

    private static func parse(_ line: String, literals: [[UInt8]]) -> ImapListStatusResponse? {
        var reader = ImapLineTokenReader(line: line, literals: literals)
        guard let token = reader.readToken(), token.type == .asterisk else { return nil }
        guard reader.readCaseInsensitiveAtom("LIST") else { return nil }
        guard let attributes = readAttributes(reader: &reader) else { return nil }
        guard let delimiterToken = reader.readToken() else { return nil }
        let delimiter = readStringValue(token: delimiterToken, reader: &reader, allowNil: true)
        guard let mailboxToken = reader.readToken() else { return nil }
        guard let mailboxName = readStringValue(token: mailboxToken, reader: &reader, allowNil: false) else { return nil }
        let mailbox = ImapMailbox(kind: .list, name: mailboxName, delimiter: delimiter, attributes: attributes)
        guard let statusItems = readStatusItems(reader: &reader) else { return nil }
        return ImapListStatusResponse(mailbox: mailbox, statusItems: statusItems)
    }

    private static func readAttributes(reader: inout ImapLineTokenReader) -> [String]? {
        guard let token = reader.readToken(), token.type == .openParen else { return nil }
        var attributes: [String] = []
        while let next = reader.readToken() {
            if next.type == .closeParen {
                break
            }
            if let value = next.stringValue {
                attributes.append(value)
            } else if next.type == .literal, let value = reader.literalString(for: next) {
                attributes.append(value)
            }
        }
        return attributes
    }

    private static func readStatusItems(reader: inout ImapLineTokenReader) -> [String: Int]? {
        guard let token = reader.readToken(), token.type == .openParen else { return nil }
        var items: [String: Int] = [:]

        if let next = reader.peekToken(),
           next.type == .atom,
           next.stringValue?.uppercased() == "STATUS"
        {
            _ = reader.readToken()
            guard let inner = reader.readToken(), inner.type == .openParen else { return nil }
            readStatusPairs(reader: &reader, items: &items)
            discardUntilClosingParen(reader: &reader)
            return items
        }

        readStatusPairs(reader: &reader, items: &items)
        return items
    }

    private static func readStatusPairs(reader: inout ImapLineTokenReader, items: inout [String: Int]) {
        while let next = reader.peekToken() {
            if next.type == .closeParen {
                _ = reader.readToken()
                break
            }
            guard let keyToken = reader.readToken(),
                  let key = readStringValue(token: keyToken, reader: &reader, allowNil: false) else {
                _ = reader.readToken()
                continue
            }
            let value = reader.readNumber() ?? 0
            items[key.uppercased()] = value
        }
    }

    private static func discardUntilClosingParen(reader: inout ImapLineTokenReader) {
        var depth = 1
        while let token = reader.readToken() {
            if token.type == .openParen {
                depth += 1
            } else if token.type == .closeParen {
                depth -= 1
                if depth == 0 {
                    break
                }
            }
        }
    }

    private static func readStringValue(
        token: ImapToken,
        reader: inout ImapLineTokenReader,
        allowNil: Bool
    ) -> String? {
        switch token.type {
        case .atom, .qString, .flag:
            return token.stringValue
        case .literal:
            return reader.literalString(for: token)
        case .nilValue:
            return allowNil ? nil : nil
        default:
            return nil
        }
    }
}
