//
// NtlmTargetInfoTests.swift
//
// Tests for NTLM Target Information parsing and encoding.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("NTLM TargetInfo empty creation")
func ntlmTargetInfoEmpty() {
    let info = NtlmTargetInfo()

    #expect(info.serverName == nil)
    #expect(info.domainName == nil)
    #expect(info.dnsServerName == nil)
    #expect(info.dnsDomainName == nil)
    #expect(info.dnsTreeName == nil)
    #expect(info.flags == nil)
    #expect(info.timestamp == nil)
    #expect(info.targetName == nil)
    #expect(info.channelBinding == nil)
}

@Test("NTLM TargetInfo encode/decode roundtrip")
func ntlmTargetInfoRoundtrip() throws {
    var info = NtlmTargetInfo()
    info.serverName = "SERVER01"
    info.domainName = "DOMAIN"
    info.dnsServerName = "server01.domain.com"
    info.dnsDomainName = "domain.com"
    info.flags = 0x02
    info.timestamp = 132_000_000_000_000_000

    let encoded = info.encode(unicode: true)
    let decoded = try NtlmTargetInfo(data: encoded, unicode: true)

    #expect(decoded.serverName == "SERVER01")
    #expect(decoded.domainName == "DOMAIN")
    #expect(decoded.dnsServerName == "server01.domain.com")
    #expect(decoded.dnsDomainName == "domain.com")
    #expect(decoded.flags == 0x02)
    #expect(decoded.timestamp == 132_000_000_000_000_000)
}

@Test("NTLM TargetInfo decode basic AV_PAIRs")
func ntlmTargetInfoDecodeBasic() throws {
    // Build a simple target info with domain and server names
    var data = Data()

    // MsvAvNbDomainName (2) = "TEST"
    data.appendInt16LE(2)  // Type
    let domainData = "TEST".data(using: .utf16LittleEndian)!
    data.appendInt16LE(Int16(domainData.count))
    data.append(domainData)

    // MsvAvNbComputerName (1) = "SERVER"
    data.appendInt16LE(1)  // Type
    let serverData = "SERVER".data(using: .utf16LittleEndian)!
    data.appendInt16LE(Int16(serverData.count))
    data.append(serverData)

    // MsvAvEOL (0)
    data.appendInt16LE(0)
    data.appendInt16LE(0)

    let info = try NtlmTargetInfo(data: data, unicode: true)

    #expect(info.domainName == "TEST")
    #expect(info.serverName == "SERVER")
}

@Test("NTLM TargetInfo decode with timestamp")
func ntlmTargetInfoWithTimestamp() throws {
    var data = Data()

    // MsvAvTimestamp (7)
    data.appendInt16LE(7)
    data.appendInt16LE(8)  // Length = 8 bytes
    let timestamp: Int64 = 132_500_000_000_000_000
    data.appendInt64LE(timestamp)

    // MsvAvEOL (0)
    data.appendInt16LE(0)
    data.appendInt16LE(0)

    let info = try NtlmTargetInfo(data: data, unicode: true)

    #expect(info.timestamp == timestamp)
}

@Test("NTLM TargetInfo decode with flags")
func ntlmTargetInfoWithFlags() throws {
    var data = Data()

    // MsvAvFlags (6)
    data.appendInt16LE(6)
    data.appendInt16LE(4)  // Length = 4 bytes
    data.appendInt32LE(0x02)  // MIC flag

    // MsvAvEOL (0)
    data.appendInt16LE(0)
    data.appendInt16LE(0)

    let info = try NtlmTargetInfo(data: data, unicode: true)

    #expect(info.flags == 0x02)
}

@Test("NTLM TargetInfo copy")
func ntlmTargetInfoCopy() {
    var original = NtlmTargetInfo()
    original.serverName = "SERVER"
    original.domainName = "DOMAIN"
    original.timestamp = 123_456_789

    let copy = original.copy()

    #expect(copy.serverName == "SERVER")
    #expect(copy.domainName == "DOMAIN")
    #expect(copy.timestamp == 123_456_789)
}

@Test("NTLM TargetInfo OEM encoding")
func ntlmTargetInfoOemEncoding() throws {
    var info = NtlmTargetInfo()
    info.serverName = "SERVER"
    info.domainName = "DOMAIN"

    // Encode as OEM (UTF-8)
    let encoded = info.encode(unicode: false)
    let decoded = try NtlmTargetInfo(data: encoded, unicode: false)

    #expect(decoded.serverName == "SERVER")
    #expect(decoded.domainName == "DOMAIN")
}
