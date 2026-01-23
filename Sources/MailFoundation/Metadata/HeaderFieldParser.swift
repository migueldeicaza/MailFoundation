//
// HeaderFieldParser.swift
//
// Minimal header field parser for raw header blocks.
//

import Foundation

enum HeaderFieldParser {
    static func parse(_ bytes: [UInt8]) -> [String: String] {
        if let text = String(data: Data(bytes), encoding: .isoLatin1) {
            return parse(text)
        }
        if let text = String(data: Data(bytes), encoding: .utf8) {
            return parse(text)
        }
        return [:]
    }

    static func parse(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentField: String? = nil
        var currentValue = ""

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        for line in lines {
            if line.isEmpty {
                break
            }
            if line.first == " " || line.first == "\t" {
                if currentField != nil {
                    currentValue.append(" ")
                    currentValue.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                continue
            }

            if let field = currentField {
                store(field: field, value: currentValue, into: &headers)
            }

            guard let colon = line.firstIndex(of: ":") else {
                currentField = nil
                currentValue = ""
                continue
            }

            let field = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: colon)
            let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            currentField = field.isEmpty ? nil : field
            currentValue = String(value)
        }

        if let field = currentField {
            store(field: field, value: currentValue, into: &headers)
        }

        return headers
    }

    private static func store(field: String, value: String, into headers: inout [String: String]) {
        let key = field.uppercased()
        if let existing = headers[key], !existing.isEmpty {
            headers[key] = existing + ", " + value
        } else {
            headers[key] = value
        }
    }
}
