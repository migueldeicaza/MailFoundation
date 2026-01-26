//
// NtlmUtilsTests.swift
//
// Tests for NTLM utility functions.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("NTLM username parsing - backslash format")
func ntlmParseUsernameBackslash() {
    let (user, domain) = NtlmUtils.parseUsername("DOMAIN\\user")

    #expect(user == "user")
    #expect(domain == "DOMAIN")
}

@Test("NTLM username parsing - at-sign format")
func ntlmParseUsernameAtSign() {
    let (user, domain) = NtlmUtils.parseUsername("user@domain.com")

    #expect(user == "user")
    #expect(domain == "domain.com")
}

@Test("NTLM username parsing - no domain")
func ntlmParseUsernameNoDomain() {
    let (user, domain) = NtlmUtils.parseUsername("user")

    #expect(user == "user")
    #expect(domain == nil)
}

@Test("NTLM username parsing - with fallback domain")
func ntlmParseUsernameWithFallback() {
    let (user, domain) = NtlmUtils.parseUsername("user", domain: "FALLBACK")

    #expect(user == "user")
    #expect(domain == "FALLBACK")
}

@Test("NTLM username parsing - domain in username overrides fallback")
func ntlmParseUsernameDomainOverrides() {
    let (user, domain) = NtlmUtils.parseUsername("MYDOMAIN\\user", domain: "FALLBACK")

    #expect(user == "user")
    #expect(domain == "MYDOMAIN")
}

@Test("NTLM nonce generation")
func ntlmNonceGeneration() {
    let nonce1 = NtlmUtils.nonce(8)
    let nonce2 = NtlmUtils.nonce(8)

    #expect(nonce1.count == 8)
    #expect(nonce2.count == 8)
    // Very unlikely to be equal (1 in 2^64)
    #expect(nonce1 != nonce2)
}

@Test("NTLM HMAC-MD5")
func ntlmHmacMd5() {
    let key = Data("key".utf8)
    let message = Data("The quick brown fox jumps over the lazy dog".utf8)

    let mac = NtlmUtils.hmacMd5(key: key, data: message)
    let hex = mac.map { String(format: "%02x", $0) }.joined()

    // Known HMAC-MD5 value
    #expect(hex == "80070713463e7749b90c2dc24911e275")
}

@Test("NTLM MD5")
func ntlmMd5() {
    let data = Data("Hello, World!".utf8)
    let hash = NtlmUtils.md5(data)
    let hex = hash.map { String(format: "%02x", $0) }.joined()

    #expect(hex == "65a8e27d8879283831b664bd8b7f0ad4")
}

@Test("NTLM RC4K")
func ntlmRc4k() {
    let key = Data("Key".utf8)
    let message = Data("Plaintext".utf8)

    let encrypted = NtlmUtils.rc4k(key: key, message: message)
    let expected: [UInt8] = [0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3]

    #expect(Array(encrypted) == expected)
}

@Test("NTLM NTLMv2 computation - anonymous")
func ntlmV2Anonymous() {
    let (ntResponse, lmResponse, sessionKey) = NtlmUtils.computeNtlmV2(
        serverChallenge: Data(count: 8),
        serverTimestamp: nil,
        domain: nil,
        userName: "",
        password: "",
        targetInfo: Data(),
        clientChallenge: Data(count: 8)
    )

    // Anonymous auth returns nil ntResponse and single zero byte for lmResponse
    #expect(ntResponse == nil)
    #expect(lmResponse == Data([0x00]))
    #expect(sessionKey == nil)
}

@Test("NTLM NTLMv2 computation - basic")
func ntlmV2Basic() {
    let serverChallenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    let clientChallenge = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])

    let (ntResponse, lmResponse, sessionKey) = NtlmUtils.computeNtlmV2(
        serverChallenge: serverChallenge,
        serverTimestamp: nil,
        domain: "DOMAIN",
        userName: "user",
        password: "password",
        targetInfo: Data(),
        clientChallenge: clientChallenge
    )

    // Basic verification - responses should be non-empty
    #expect(ntResponse != nil)
    #expect(ntResponse!.count > 0)
    #expect(lmResponse.count > 0)
    #expect(sessionKey != nil)
    #expect(sessionKey!.count == 16)
}

@Test("NTLM NTLMv2 computation - with server timestamp")
func ntlmV2WithTimestamp() {
    let serverChallenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    let clientChallenge = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])
    let serverTimestamp: Int64 = 132_000_000_000_000_000

    let (ntResponse, lmResponse, _) = NtlmUtils.computeNtlmV2(
        serverChallenge: serverChallenge,
        serverTimestamp: serverTimestamp,
        domain: "DOMAIN",
        userName: "user",
        password: "password",
        targetInfo: Data(),
        clientChallenge: clientChallenge
    )

    #expect(ntResponse != nil)
    // When timestamp is present, lmResponse should be Z(24)
    #expect(lmResponse == Data(count: 24))
}
