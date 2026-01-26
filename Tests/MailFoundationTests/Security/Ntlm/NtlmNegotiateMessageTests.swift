//
// NtlmNegotiateMessageTests.swift
//
// Tests for NTLM Type 1 (Negotiate) message.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("NTLM Negotiate message encoding")
func ntlmNegotiateEncode() {
    let negotiate = NtlmNegotiateMessage()
    let encoded = negotiate.encode()

    // Check signature
    #expect(encoded.count >= 12)
    #expect(encoded[0] == 0x4E)  // N
    #expect(encoded[1] == 0x54)  // T
    #expect(encoded[2] == 0x4C)  // L
    #expect(encoded[3] == 0x4D)  // M
    #expect(encoded[4] == 0x53)  // S
    #expect(encoded[5] == 0x53)  // S
    #expect(encoded[6] == 0x50)  // P
    #expect(encoded[7] == 0x00)  // NUL

    // Check type (1 as little-endian UInt32)
    #expect(encoded[8] == 0x01)
    #expect(encoded[9] == 0x00)
    #expect(encoded[10] == 0x00)
    #expect(encoded[11] == 0x00)
}

@Test("NTLM Negotiate message with domain and workstation")
func ntlmNegotiateWithDomainWorkstation() {
    let negotiate = NtlmNegotiateMessage(domain: "MYDOMAIN", workstation: "MYWORKSTATION")
    let encoded = negotiate.encode()

    #expect(negotiate.domain == "MYDOMAIN")
    #expect(negotiate.workstation == "MYWORKSTATION")
    #expect(negotiate.flags.contains(.negotiateDomainSupplied))
    #expect(negotiate.flags.contains(.negotiateWorkstationSupplied))
    #expect(encoded.count > 40)
}

@Test("NTLM Negotiate message decode roundtrip")
func ntlmNegotiateDecodeRoundtrip() throws {
    let original = NtlmNegotiateMessage(domain: "TESTDOMAIN", workstation: "TESTPC")
    let encoded = original.encode()
    let decoded = try NtlmNegotiateMessage(data: encoded)

    #expect(decoded.type == 1)
    #expect(decoded.domain == "TESTDOMAIN")
    #expect(decoded.workstation == "TESTPC")
}

@Test("NTLM Negotiate default flags")
func ntlmNegotiateDefaultFlags() {
    let negotiate = NtlmNegotiateMessage()

    #expect(negotiate.flags.contains(.negotiateUnicode))
    #expect(negotiate.flags.contains(.negotiateOem))
    #expect(negotiate.flags.contains(.requestTarget))
    #expect(negotiate.flags.contains(.negotiateNtlm))
    #expect(negotiate.flags.contains(.negotiateAlwaysSign))
    #expect(negotiate.flags.contains(.negotiateExtendedSessionSecurity))
    #expect(negotiate.flags.contains(.negotiate128))
    #expect(negotiate.flags.contains(.negotiate56))
}

@Test("NTLM Negotiate invalid signature throws")
func ntlmNegotiateInvalidSignature() {
    let badData = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])

    #expect(throws: NtlmError.self) {
        _ = try NtlmNegotiateMessage(data: badData)
    }
}

@Test("NTLM Negotiate wrong type throws")
func ntlmNegotiateWrongType() {
    // Valid NTLM signature but wrong type (2 instead of 1)
    let wrongType = Data([
        0x4E, 0x54, 0x4C, 0x4D, 0x53, 0x53, 0x50, 0x00,  // NTLMSSP\0
        0x02, 0x00, 0x00, 0x00,  // Type 2
    ])

    #expect(throws: NtlmError.invalidMessageType(expected: 1, actual: 2)) {
        _ = try NtlmNegotiateMessage(data: wrongType)
    }
}
