//
// RC4Tests.swift
//
// Tests for RC4 stream cipher implementation.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("RC4 basic encryption")
func rc4BasicEncryption() {
    // Test vector from Wikipedia
    let key = Data("Key".utf8)
    let plaintext = Data("Plaintext".utf8)

    let rc4 = RC4(key: key)
    let ciphertext = rc4.transform(plaintext)

    // Known RC4 output for this key/plaintext
    let expected: [UInt8] = [0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3]
    #expect(Array(ciphertext) == expected)
}

@Test("RC4 decryption")
func rc4Decryption() {
    // RC4 is symmetric - encryption and decryption are the same operation
    let key = Data("Key".utf8)
    let ciphertext = Data([0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3])

    let rc4 = RC4(key: key)
    let plaintext = rc4.transform(ciphertext)

    #expect(String(data: plaintext, encoding: .utf8) == "Plaintext")
}

@Test("RC4 roundtrip")
func rc4Roundtrip() {
    let key = Data("SecretKey123".utf8)
    let original = Data("Hello, World! This is a test message for RC4.".utf8)

    let encrypted = RC4.transform(key: key, message: original)
    let decrypted = RC4.transform(key: key, message: encrypted)

    #expect(decrypted == original)
}

@Test("RC4 Wiki test vector")
func rc4WikiTestVector() {
    // Test vector: Key = "Wiki", Plaintext = "pedia"
    let key = Data("Wiki".utf8)
    let plaintext = Data("pedia".utf8)

    let rc4 = RC4(key: key)
    let ciphertext = rc4.transform(plaintext)

    // Expected ciphertext
    let expected: [UInt8] = [0x10, 0x21, 0xBF, 0x04, 0x20]
    #expect(Array(ciphertext) == expected)
}

@Test("RC4 Secret test vector")
func rc4SecretTestVector() {
    // Test vector: Key = "Secret", Plaintext = "Attack at dawn"
    let key = Data("Secret".utf8)
    let plaintext = Data("Attack at dawn".utf8)

    let rc4 = RC4(key: key)
    let ciphertext = rc4.transform(plaintext)

    // Expected ciphertext
    let expected: [UInt8] = [
        0x45, 0xA0, 0x1F, 0x64, 0x5F, 0xC3, 0x5B, 0x38, 0x35, 0x52, 0x54, 0x4B, 0x9B, 0xF5,
    ]
    #expect(Array(ciphertext) == expected)
}
