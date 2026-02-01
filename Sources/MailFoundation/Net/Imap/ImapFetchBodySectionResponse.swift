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
// ImapFetchBodySectionResponse.swift
//
// Parse FETCH BODY[] literal responses.
//

public struct ImapFetchBodySectionResponse: Sendable, Equatable {
    public let sequence: Int
    public let section: ImapFetchBodySection?
    public let peek: Bool
    public let partial: ImapFetchPartial?
    public let data: [UInt8]

    private static func debugLog(_ message: String) {
        MailFoundationLogging.debug(.imapFetch, message)
    }

    /// Parses the first BODY[] or BODY.PEEK[] literal section from a FETCH response message.
    ///
    /// - Parameter message: The literal message containing a FETCH response.
    /// - Returns: The parsed body section response, or `nil` if parsing fails.
    public static func parse(_ message: ImapLiteralMessage) -> ImapFetchBodySectionResponse? {
        parseAll(message).first
    }

    public static func parsePayload(_ payload: String, sequence: Int, data: [UInt8]) -> ImapFetchBodySectionResponse? {
        let upper = payload.uppercased()
        guard let bodyRange = upper.range(of: "BODY") else { return nil }
        var index = bodyRange.lowerBound
        var peek = false

        if upper[index...].hasPrefix("BODY.PEEK[") {
            peek = true
            index = upper.index(index, offsetBy: "BODY.PEEK[".count)
        } else if upper[index...].hasPrefix("BODY[") {
            index = upper.index(index, offsetBy: "BODY[".count)
        } else {
            return nil
        }

        let startIndex = index
        while index < payload.endIndex, payload[index] != "]" {
            index = payload.index(after: index)
        }
        guard index < payload.endIndex else { return nil }
        let sectionText = String(payload[startIndex..<index])
        let section = sectionText.isEmpty ? nil : ImapFetchBodySection.parse(sectionText)
        index = payload.index(after: index)

        let partial = parsePartial(from: payload[index...])
        return ImapFetchBodySectionResponse(sequence: sequence, section: section, peek: peek, partial: partial, data: data)
    }

    /// Parses all BODY[] and BODY.PEEK[] literal sections from a FETCH response message.
    ///
    /// - Parameter message: The literal message containing a FETCH response.
    /// - Returns: An array of parsed sections (empty if none).
    public static func parseAll(_ message: ImapLiteralMessage) -> [ImapFetchBodySectionResponse] {
        var reader = ImapLineTokenReader(line: message.line, literals: message.literals)
        guard let token = reader.readToken(), token.type == .asterisk else { return [] }
        guard let sequence = reader.readNumber() else { return [] }
        guard reader.readCaseInsensitiveAtom("FETCH") else { return [] }
        guard let open = reader.readToken(), open.type == .openParen else { return [] }

        var results: [ImapFetchBodySectionResponse] = []

        while let next = reader.peekToken() {
            if next.type == .closeParen {
                _ = reader.readToken()
                break
            }
            guard let nameToken = reader.readToken(),
                  nameToken.type == .atom,
                  let name = nameToken.stringValue else {
                return results
            }
            let upper = name.uppercased()
            if upper == "BODY" || upper == "BODY.PEEK" {
                let peek = upper == "BODY.PEEK"
                var section: ImapFetchBodySection?
                if let bracket = reader.peekToken(), bracket.type == .openBracket {
                    if let sectionText = reader.readBracketedContent(materializeLiterals: true) {
                        let trimmed = sectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        section = trimmed.isEmpty ? nil : ImapFetchBodySection.parse(trimmed)
                    }
                } else {
                    reader.skipValue()
                    continue
                }

                var partial: ImapFetchPartial?
                var partialStart: Int?
                if let partialToken = reader.peekToken(),
                   partialToken.type == .atom,
                   let partialValue = partialToken.stringValue,
                   partialValue.hasPrefix("<"),
                   partialValue.hasSuffix(">") {
                    _ = reader.readToken()
                    partial = parsePartial(fromAtom: partialValue)
                    if partial == nil {
                        partialStart = parsePartialStart(fromAtom: partialValue)
                    }
                }

                guard let dataToken = reader.readToken() else { continue }
                switch dataToken.type {
                case .literal:
                    if let data = reader.literalBytes(for: dataToken) {
                        if partial == nil, let start = partialStart, data.isEmpty == false {
                            partial = ImapFetchPartial(start: start, length: data.count)
                        }
                        results.append(ImapFetchBodySectionResponse(
                            sequence: sequence,
                            section: section,
                            peek: peek,
                            partial: partial,
                            data: data
                        ))
                    }
                case .qString, .atom, .flag:
                    if let value = dataToken.stringValue {
                        let data = Array(value.utf8)
                        if partial == nil, let start = partialStart, data.isEmpty == false {
                            partial = ImapFetchPartial(start: start, length: data.count)
                        }
                        results.append(ImapFetchBodySectionResponse(
                            sequence: sequence,
                            section: section,
                            peek: peek,
                            partial: partial,
                            data: data
                        ))
                    }
                case .nilValue:
                    break
                default:
                    break
                }
            } else {
                reader.skipValue()
            }
        }

        if results.isEmpty {
            debugLog("[BodySectionResponse.parseAll] No BODY literal in message, line='\(message.line.prefix(60))'")
        }
        return results
    }

    private static func parsePartial(from text: Substring) -> ImapFetchPartial? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "<", let endIndex = trimmed.firstIndex(of: ">") else { return nil }
        let inner = trimmed[trimmed.index(after: trimmed.startIndex)..<endIndex]
        let parts = inner.split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count == 2, let start = Int(parts[0]), let length = Int(parts[1]) else {
            return nil
        }
        return ImapFetchPartial(start: start, length: length)
    }

    private static func parsePartial(fromAtom atom: String) -> ImapFetchPartial? {
        guard atom.first == "<", atom.last == ">" else { return nil }
        let inner = atom.dropFirst().dropLast()
        let parts = inner.split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count == 2, let start = Int(parts[0]), let length = Int(parts[1]) else {
            return nil
        }
        return ImapFetchPartial(start: start, length: length)
    }

    private static func parsePartialStart(fromAtom atom: String) -> Int? {
        guard atom.first == "<", atom.last == ">" else { return nil }
        let inner = atom.dropFirst().dropLast()
        guard inner.contains(".") == false, let start = Int(inner) else { return nil }
        return start
    }
}
