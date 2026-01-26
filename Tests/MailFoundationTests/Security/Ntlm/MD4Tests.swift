//
// MD4Tests.swift
//
// Tests for MD4 hash implementation.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("MD4 empty string hash")
func md4EmptyString() {
    let md4 = MD4()
    let hash = md4.computeHash(Data())
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector: "" -> 31d6cfe0d16ae931b73c59d7e0c089c0
    #expect(hex == "31d6cfe0d16ae931b73c59d7e0c089c0")
}

@Test("MD4 'a' hash")
func md4SingleChar() {
    let md4 = MD4()
    let hash = md4.computeHash(Data("a".utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector: "a" -> bde52cb31de33e46245e05fbdbd6fb24
    #expect(hex == "bde52cb31de33e46245e05fbdbd6fb24")
}

@Test("MD4 'abc' hash")
func md4Abc() {
    let md4 = MD4()
    let hash = md4.computeHash(Data("abc".utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector: "abc" -> a448017aaf21d8525fc10ae87aa6729d
    #expect(hex == "a448017aaf21d8525fc10ae87aa6729d")
}

@Test("MD4 'message digest' hash")
func md4MessageDigest() {
    let md4 = MD4()
    let hash = md4.computeHash(Data("message digest".utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector: "message digest" -> d9130a8164549fe818874806e1c7014b
    #expect(hex == "d9130a8164549fe818874806e1c7014b")
}

@Test("MD4 lowercase alphabet hash")
func md4Alphabet() {
    let md4 = MD4()
    let hash = md4.computeHash(Data("abcdefghijklmnopqrstuvwxyz".utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector: "abcdefghijklmnopqrstuvwxyz" -> d79e1c308aa5bbcdeea8ed63df412da9
    #expect(hex == "d79e1c308aa5bbcdeea8ed63df412da9")
}

@Test("MD4 alphanumeric hash")
func md4Alphanumeric() {
    let md4 = MD4()
    let hash = md4.computeHash(Data("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector -> 043f8582f241db351ce627e153e7f0e4
    #expect(hex == "043f8582f241db351ce627e153e7f0e4")
}

@Test("MD4 numeric hash")
func md4Numeric() {
    let md4 = MD4()
    let input = "12345678901234567890123456789012345678901234567890123456789012345678901234567890"
    let hash = md4.computeHash(Data(input.utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // RFC 1320 test vector -> e33b4ddc9c38f2199c3e7b164fcc0536
    #expect(hex == "e33b4ddc9c38f2199c3e7b164fcc0536")
}

@Test("MD4 sample text hash")
func md4SampleText() {
    let md4 = MD4()
    let text = "This is some sample text that we will hash using the MD4 algorithm."
    let hash = md4.computeHash(Data(text.utf8))
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    // Known value from MailKit tests
    #expect(hex == "69b390afdf693eae92ebea5cc6669b3f")
}
