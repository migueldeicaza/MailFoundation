//
// SubjectDecoder.swift
//
// RFC 2047 subject decoding helper using SwiftMimeKit.
//

import SwiftMimeKit

public enum SubjectDecoder {
    public static func decode(_ rawValue: String) -> String {
        let headerText = "Subject: \(rawValue)"
        if let header = try? Header.parse(headerText) {
            return header.value
        }
        return rawValue
    }
}
