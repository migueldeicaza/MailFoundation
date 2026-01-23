//
// ImapBodyStructure.swift
//
// IMAP BODYSTRUCTURE parser (minimal).
//

import Foundation

public struct ImapContentDisposition: Sendable, Equatable {
    public let type: String
    public let parameters: [String: String]
}

public struct ImapBodyPart: Sendable, Equatable {
    public let type: String
    public let subtype: String
    public let parameters: [String: String]
    public let id: String?
    public let description: String?
    public let encoding: String?
    public let size: Int?
    public let lines: Int?
    public let md5: String?
    public let envelopeRaw: String?
    public let embedded: ImapBodyStructure?
    public let disposition: ImapContentDisposition?
    public let language: [String]?
    public let location: String?
    public let extensions: [String]
}

public struct ImapMultipart: Sendable, Equatable {
    public let parts: [ImapBodyStructure]
    public let subtype: String
    public let parameters: [String: String]
    public let disposition: ImapContentDisposition?
    public let language: [String]?
    public let location: String?
    public let extensions: [String]
}

public indirect enum ImapBodyStructure: Sendable, Equatable {
    case single(ImapBodyPart)
    case multipart(ImapMultipart)

    public static func parse(_ text: String) -> ImapBodyStructure? {
        var parser = ImapBodyStructureParser(text: text)
        guard let node = parser.parse() else {
            return nil
        }
        return parseNode(node)
    }
}

private enum ImapBodyNode: Equatable {
    case list([ImapBodyNode])
    case string(String)
    case number(Int)
    case nilValue
}

private struct ImapBodyStructureParser {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(text: String) {
        self.bytes = Array(text.utf8)
    }

    mutating func parse() -> ImapBodyNode? {
        skipWhitespace()
        guard let node = parseNode() else { return nil }
        return node
    }

    private mutating func parseNode() -> ImapBodyNode? {
        skipWhitespace()
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        if byte == 40 { // '('
            index += 1
            var items: [ImapBodyNode] = []
            while true {
                skipWhitespace()
                if index >= bytes.count {
                    return nil
                }
                if bytes[index] == 41 { // ')'
                    index += 1
                    break
                }
                guard let item = parseNode() else { return nil }
                items.append(item)
            }
            return .list(items)
        }
        if byte == 34 { // '"'
            return parseQuoted()
        }
        if byte == 123 { // '{'
            return parseLiteral()
        }
        return parseAtom()
    }

    private mutating func parseQuoted() -> ImapBodyNode? {
        guard index < bytes.count, bytes[index] == 34 else { return nil }
        index += 1
        var output: [UInt8] = []
        var escape = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if escape {
                output.append(byte)
                escape = false
                continue
            }
            if byte == 92 { // '\\'
                escape = true
                continue
            }
            if byte == 34 { // '"'
                return .string(String(decoding: output, as: UTF8.self))
            }
            output.append(byte)
        }
        return nil
    }

    private mutating func parseLiteral() -> ImapBodyNode? {
        guard index < bytes.count, bytes[index] == 123 else { return nil }
        index += 1
        var countValue: Int = 0
        var hasDigits = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 125 { // '}'
                index += 1
                break
            }
            guard byte >= 48, byte <= 57 else { return nil }
            hasDigits = true
            countValue = countValue * 10 + Int(byte - 48)
            index += 1
        }
        guard hasDigits else { return nil }
        if index + 1 < bytes.count, bytes[index] == 13, bytes[index + 1] == 10 {
            index += 2
        }
        guard index + countValue <= bytes.count else { return nil }
        let literalBytes = Array(bytes[index..<index + countValue])
        index += countValue
        return .string(String(decoding: literalBytes, as: UTF8.self))
    }

    private mutating func parseAtom() -> ImapBodyNode? {
        let start = index
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 40 || byte == 41 {
                break
            }
            index += 1
        }
        guard start < index else { return nil }
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        if token.uppercased() == "NIL" {
            return .nilValue
        }
        if let number = Int(token) {
            return .number(number)
        }
        return .string(token)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 {
                index += 1
            } else {
                break
            }
        }
    }
}

private func parseNode(_ node: ImapBodyNode) -> ImapBodyStructure? {
    guard case let .list(items) = node else { return nil }
    guard !items.isEmpty else { return nil }

    if case .list = items[0] {
        return parseMultipart(items)
    }
    return parseSingle(items)
}

private func parseMultipart(_ items: [ImapBodyNode]) -> ImapBodyStructure? {
    var parts: [ImapBodyStructure] = []
    var index = 0
    while index < items.count {
        if case .list = items[index] {
            if let part = parseNode(items[index]) {
                parts.append(part)
                index += 1
                continue
            }
            return nil
        }
        break
    }

    guard index < items.count, let subtype = nodeString(items[index]) else { return nil }
    index += 1

    var parameters: [String: String] = [:]
    if index < items.count, let params = parseParameters(items[index]) {
        parameters = params
        index += 1
    } else if index < items.count, case .nilValue = items[index] {
        index += 1
    }

    let disposition = parseDisposition(from: items, index: &index)
    let language = parseLanguage(from: items, index: &index)
    let location = parseLocation(from: items, index: &index)
    let extensions = parseExtensions(from: items, index: &index)

    let multipart = ImapMultipart(
        parts: parts,
        subtype: subtype,
        parameters: parameters,
        disposition: disposition,
        language: language,
        location: location,
        extensions: extensions
    )
    return .multipart(multipart)
}

private func parseSingle(_ items: [ImapBodyNode]) -> ImapBodyStructure? {
    guard items.count >= 7 else { return nil }
    guard let type = nodeString(items[0]), let subtype = nodeString(items[1]) else { return nil }
    let parameters = parseParameters(items[2]) ?? [:]
    let id = nodeString(items[3])
    let description = nodeString(items[4])
    let encoding = nodeString(items[5])
    let size = nodeInt(items[6])

    var index = 7
    var lines: Int?
    var envelopeRaw: String?
    var embedded: ImapBodyStructure?

    if type.uppercased() == "TEXT", index < items.count {
        lines = nodeInt(items[index])
        index += 1
    } else if type.uppercased() == "MESSAGE", subtype.uppercased() == "RFC822" {
        if index < items.count {
            envelopeRaw = renderNode(items[index])
            index += 1
        }
        if index < items.count {
            embedded = parseNode(items[index])
            index += 1
        }
        if index < items.count {
            lines = nodeInt(items[index])
            index += 1
        }
    }

    let md5 = parseOptionalString(from: items, index: &index)
    let disposition = parseDisposition(from: items, index: &index)
    let language = parseLanguage(from: items, index: &index)
    let location = parseLocation(from: items, index: &index)
    let extensions = parseExtensions(from: items, index: &index)

    let part = ImapBodyPart(
        type: type,
        subtype: subtype,
        parameters: parameters,
        id: id,
        description: description,
        encoding: encoding,
        size: size,
        lines: lines,
        md5: md5,
        envelopeRaw: envelopeRaw,
        embedded: embedded,
        disposition: disposition,
        language: language,
        location: location,
        extensions: extensions
    )
    return .single(part)
}

private func parseParameters(_ node: ImapBodyNode) -> [String: String]? {
    guard case let .list(items) = node else { return nil }
    var result: [String: String] = [:]
    var index = 0
    while index + 1 < items.count {
        guard let key = nodeString(items[index]) else { return nil }
        guard let value = nodeString(items[index + 1]) else { return nil }
        result[key.uppercased()] = value
        index += 2
    }
    return result
}

private func parseDisposition(from items: [ImapBodyNode], index: inout Int) -> ImapContentDisposition? {
    guard index < items.count else { return nil }
    if case .nilValue = items[index] {
        index += 1
        return nil
    }
    guard case let .list(values) = items[index], values.count >= 1 else { return nil }
    guard let type = nodeString(values[0]) else { return nil }
    var parameters: [String: String] = [:]
    if values.count > 1, let params = parseParameters(values[1]) {
        parameters = params
    }
    index += 1
    return ImapContentDisposition(type: type, parameters: parameters)
}

private func parseLanguage(from items: [ImapBodyNode], index: inout Int) -> [String]? {
    guard index < items.count else { return nil }
    let node = items[index]
    if let value = nodeString(node) {
        index += 1
        return [value]
    }
    if case .nilValue = node {
        index += 1
        return nil
    }
    if case let .list(values) = node {
        let langs = values.compactMap(nodeString)
        index += 1
        return langs.isEmpty ? nil : langs
    }
    return nil
}

private func parseLocation(from items: [ImapBodyNode], index: inout Int) -> String? {
    guard index < items.count else { return nil }
    if let value = nodeString(items[index]) {
        index += 1
        return value
    }
    if case .nilValue = items[index] {
        index += 1
        return nil
    }
    return nil
}

private func parseOptionalString(from items: [ImapBodyNode], index: inout Int) -> String? {
    guard index < items.count else { return nil }
    let node = items[index]
    if case .nilValue = node {
        index += 1
        return nil
    }
    if let value = nodeString(node) {
        index += 1
        return value
    }
    return nil
}

private func parseExtensions(from items: [ImapBodyNode], index: inout Int) -> [String] {
    guard index < items.count else { return [] }
    var result: [String] = []
    while index < items.count {
        result.append(renderNode(items[index]))
        index += 1
    }
    return result
}

private func nodeString(_ node: ImapBodyNode) -> String? {
    switch node {
    case .string(let value):
        return value
    case .number(let value):
        return String(value)
    default:
        return nil
    }
}

private func nodeInt(_ node: ImapBodyNode) -> Int? {
    switch node {
    case .number(let value):
        return value
    case .string(let value):
        return Int(value)
    default:
        return nil
    }
}

private func renderNode(_ node: ImapBodyNode) -> String {
    switch node {
    case .nilValue:
        return "NIL"
    case .number(let value):
        return String(value)
    case .string(let value):
        return quote(value)
    case .list(let items):
        let inner = items.map { renderNode($0) }.joined(separator: " ")
        return "(\(inner))"
    }
}

private func quote(_ value: String) -> String {
    var result = "\""
    for ch in value {
        if ch == "\\" || ch == "\"" {
            result.append("\\")
        }
        result.append(ch)
    }
    result.append("\"")
    return result
}
