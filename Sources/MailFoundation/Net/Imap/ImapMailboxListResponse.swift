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
// ImapMailboxListResponse.swift
//
// IMAP LIST/LSUB response parsing.
//

import Foundation

public enum ImapMailboxListKind: Sendable {
    case list
    case lsub
}

public struct ImapMailboxListResponse: Sendable, Equatable {
    public let kind: ImapMailboxListKind
    public let attributes: [String]
    public let delimiter: String?
    public let name: String
    public let decodedName: String

    public init(kind: ImapMailboxListKind, attributes: [String], delimiter: String?, name: String) {
        self.kind = kind
        self.attributes = attributes
        self.delimiter = delimiter
        self.name = name
        self.decodedName = ImapMailboxEncoding.decode(name)
    }

    public static func parse(_ line: String) -> ImapMailboxListResponse? {
        parse(line, literals: [])
    }

    /// Parses a LIST or LSUB response from a literal-aware message.
    ///
    /// - Parameter message: The literal response message.
    /// - Returns: The parsed mailbox list response, or `nil` if parsing fails.
    public static func parse(_ message: ImapLiteralMessage) -> ImapMailboxListResponse? {
        parse(message.line, literals: message.literals)
    }

    private static func parse(_ line: String, literals: [[UInt8]]) -> ImapMailboxListResponse? {
        var reader = ImapLineTokenReader(line: line, literals: literals)
        guard let token = reader.readToken(), token.type == .asterisk else { return nil }
        guard let commandToken = reader.readToken(),
              commandToken.type == .atom,
              let command = commandToken.stringValue else {
            return nil
        }
        let upper = command.uppercased()
        let kind: ImapMailboxListKind
        if upper == "LIST" || upper == "XLIST" {
            kind = .list
        } else if upper == "LSUB" {
            kind = .lsub
        } else {
            return nil
        }

        guard let attributes = readAttributes(reader: &reader) else { return nil }
        guard let delimiterToken = reader.readToken() else { return nil }
        let delimiter = readStringValue(token: delimiterToken, reader: &reader, allowNil: true)
        guard let mailboxToken = reader.readToken() else { return nil }
        guard let name = readStringValue(token: mailboxToken, reader: &reader, allowNil: false) else { return nil }

        return ImapMailboxListResponse(kind: kind, attributes: attributes, delimiter: delimiter, name: name)
    }

    private static func readAttributes(reader: inout ImapLineTokenReader) -> [String]? {
        guard let token = reader.readToken(), token.type == .openParen else { return nil }
        var result: [String] = []
        while let next = reader.readToken() {
            if next.type == .closeParen {
                break
            }
            if let value = next.stringValue {
                result.append(value)
            } else if next.type == .literal, let value = reader.literalString(for: next) {
                result.append(value)
            }
        }
        return result
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
