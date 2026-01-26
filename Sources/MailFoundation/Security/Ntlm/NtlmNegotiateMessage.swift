//
// NtlmNegotiateMessage.swift
//
// NTLM Type 1 (Negotiate) message.
//
// Port of MailKit's NtlmNegotiateMessage.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// NTLM Type 1 (Negotiate) message.
///
/// This message is sent by the client to initiate NTLM authentication.
/// It contains the client's supported capabilities and optional domain/workstation information.
public struct NtlmNegotiateMessage: NtlmMessage, Sendable {
    public let type = 1

    /// The negotiation flags.
    public let flags: NtlmFlags

    /// The client's domain name (optional).
    public let domain: String

    /// The client's workstation name (optional).
    public let workstation: String

    /// The OS version (optional, only included if `negotiateVersion` flag is set).
    public let osVersion: (major: Int, minor: Int, build: Int)?

    /// Creates a new negotiate message with the default flags.
    ///
    /// - Parameters:
    ///   - domain: The client's domain name (optional).
    ///   - workstation: The client's workstation name (optional).
    ///   - osVersion: The OS version tuple (optional). If provided, the `negotiateVersion`
    ///                flag will be set and domain/workstation will be cleared per the spec.
    public init(domain: String? = nil, workstation: String? = nil, osVersion: (Int, Int, Int)? = nil) {
        self.init(flags: .defaultNegotiate, domain: domain, workstation: workstation, osVersion: osVersion)
    }

    /// Creates a new negotiate message with custom flags.
    ///
    /// - Parameters:
    ///   - flags: The negotiation flags.
    ///   - domain: The client's domain name (optional).
    ///   - workstation: The client's workstation name (optional).
    ///   - osVersion: The OS version tuple (optional). If provided, the `negotiateVersion`
    ///                flag will be set and domain/workstation will be cleared per the spec.
    public init(flags: NtlmFlags, domain: String? = nil, workstation: String? = nil, osVersion: (Int, Int, Int)? = nil) {
        var finalFlags = flags.subtracting([.negotiateDomainSupplied, .negotiateWorkstationSupplied, .negotiateVersion])

        // Per spec: If NTLMSSP_NEGOTIATE_VERSION is set, domain and workstation MUST be empty
        if let osVersion = osVersion {
            finalFlags.insert(.negotiateVersion)
            self.osVersion = osVersion
            self.domain = ""
            self.workstation = ""
        } else {
            self.osVersion = nil

            if let domain = domain, !domain.isEmpty {
                finalFlags.insert(.negotiateDomainSupplied)
                self.domain = domain.uppercased()
            } else {
                self.domain = ""
            }

            if let workstation = workstation, !workstation.isEmpty {
                finalFlags.insert(.negotiateWorkstationSupplied)
                self.workstation = workstation.uppercased()
            } else {
                self.workstation = ""
            }
        }

        self.flags = finalFlags
    }

    /// Decodes a negotiate message from binary data.
    ///
    /// - Parameter data: The message data.
    /// - Throws: `NtlmError` if the message is invalid.
    public init(data: Data) throws {
        try NtlmMessageUtils.validateMessage(data, expectedType: 1)

        let flags = NtlmFlags(rawValue: data.readUInt32LE(at: 12))
        self.flags = flags

        // Decode domain
        let domainLength = Int(data.readUInt16LE(at: 16))
        let domainOffset = Int(data.readUInt16LE(at: 20))
        if domainLength > 0, domainOffset + domainLength <= data.count {
            let domainData = data.subdata(in: domainOffset..<(domainOffset + domainLength))
            self.domain = String(data: domainData, encoding: .utf8) ?? ""
        } else {
            self.domain = ""
        }

        // Decode workstation
        let workstationLength = Int(data.readUInt16LE(at: 24))
        let workstationOffset = Int(data.readUInt16LE(at: 28))
        if workstationLength > 0, workstationOffset + workstationLength <= data.count {
            let workstationData = data.subdata(in: workstationOffset..<(workstationOffset + workstationLength))
            self.workstation = String(data: workstationData, encoding: .utf8) ?? ""
        } else {
            self.workstation = ""
        }

        // Decode OS version if present
        if flags.contains(.negotiateVersion), data.count >= 40 {
            let major = Int(data[32])
            let minor = Int(data[33])
            let build = Int(data.readUInt16LE(at: 34))
            self.osVersion = (major, minor, build)
        } else {
            self.osVersion = nil
        }
    }

    /// Encodes the message to binary data.
    public func encode() -> Data {
        let domainBytes = domain.data(using: .utf8) ?? Data()
        let workstationBytes = workstation.data(using: .utf8) ?? Data()
        let versionLength = 8

        let workstationOffset = 32 + versionLength
        let domainOffset = workstationOffset + workstationBytes.count

        var message = NtlmMessageUtils.prepareMessage(
            size: 32 + versionLength + domainBytes.count + workstationBytes.count,
            type: 1
        )

        // Flags (4 bytes at offset 12)
        message.writeUInt32LE(flags.rawValue, at: 12)

        // Domain security buffer (8 bytes at offset 16)
        message.writeUInt16LE(UInt16(domainBytes.count), at: 16)  // Length
        message.writeUInt16LE(UInt16(domainBytes.count), at: 18)  // MaxLength
        message.writeUInt16LE(UInt16(domainOffset), at: 20)  // Offset

        // Workstation security buffer (8 bytes at offset 24)
        message.writeUInt16LE(UInt16(workstationBytes.count), at: 24)  // Length
        message.writeUInt16LE(UInt16(workstationBytes.count), at: 26)  // MaxLength
        message.writeUInt16LE(UInt16(workstationOffset), at: 28)  // Offset

        // Version (8 bytes at offset 32)
        if let osVersion = osVersion {
            message[32] = UInt8(osVersion.major)
            message[33] = UInt8(osVersion.minor)
            message.writeUInt16LE(UInt16(osVersion.build), at: 34)
            message[36] = 0x00
            message[37] = 0x00
            message[38] = 0x00
            message[39] = 0x0F  // NTLM revision
        }

        // Workstation payload
        for (i, byte) in workstationBytes.enumerated() {
            message[workstationOffset + i] = byte
        }

        // Domain payload
        for (i, byte) in domainBytes.enumerated() {
            message[domainOffset + i] = byte
        }

        return message
    }
}
