//
// NtlmChallengeMessage.swift
//
// NTLM Type 2 (Challenge) message.
//
// Port of MailKit's NtlmChallengeMessage.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// NTLM Type 2 (Challenge) message.
///
/// This message is sent by the server in response to a Type 1 message.
/// It contains the server's challenge and capabilities.
public struct NtlmChallengeMessage: NtlmMessage, Sendable {
    public let type = 2

    /// The negotiation flags.
    public let flags: NtlmFlags

    /// The 8-byte server challenge (nonce).
    public let serverChallenge: Data

    /// The target name (server or domain name depending on flags).
    public let targetName: String?

    /// The target information block.
    public let targetInfo: NtlmTargetInfo?

    /// The OS version (optional).
    public let osVersion: (major: Int, minor: Int, build: Int)?

    /// Decodes a challenge message from binary data.
    ///
    /// - Parameter data: The message data.
    /// - Throws: `NtlmError` if the message is invalid.
    public init(data: Data) throws {
        try NtlmMessageUtils.validateMessage(data, expectedType: 2)

        // Flags (at offset 20)
        let flags = NtlmFlags(rawValue: data.readUInt32LE(at: 20))
        self.flags = flags

        // Server challenge (8 bytes at offset 24)
        guard data.count >= 32 else {
            throw NtlmError.messageTooShort
        }
        self.serverChallenge = data.subdata(in: 24..<32)

        // Target name
        let targetNameLength = Int(data.readUInt16LE(at: 12))
        let targetNameOffset = Int(data.readInt32LE(at: 16))
        if targetNameLength > 0, targetNameOffset > 0, targetNameOffset + targetNameLength <= data.count {
            let encoding: String.Encoding = flags.contains(.negotiateUnicode) ? .utf16LittleEndian : .utf8
            let targetNameData = data.subdata(in: targetNameOffset..<(targetNameOffset + targetNameLength))
            self.targetName = String(data: targetNameData, encoding: encoding)
        } else {
            self.targetName = nil
        }

        // OS version (at offset 48 if NegotiateVersion flag is set)
        if flags.contains(.negotiateVersion), data.count >= 56 {
            let major = Int(data[48])
            let minor = Int(data[49])
            let build = Int(data.readUInt16LE(at: 50))
            self.osVersion = (major, minor, build)
        } else {
            self.osVersion = nil
        }

        // Target info (optional, at offset 40)
        if data.count >= 48, targetNameOffset >= 48 {
            let targetInfoLength = Int(data.readUInt16LE(at: 40))
            let targetInfoOffset = Int(data.readUInt16LE(at: 44))

            if targetInfoLength > 0,
               targetInfoOffset > 0,
               targetInfoOffset < data.count,
               targetInfoLength <= (data.count - targetInfoOffset)
            {
                let targetInfoData = data.subdata(in: targetInfoOffset..<(targetInfoOffset + targetInfoLength))
                self.targetInfo = try? NtlmTargetInfo(data: targetInfoData, unicode: flags.contains(.negotiateUnicode))
            } else {
                self.targetInfo = nil
            }
        } else {
            self.targetInfo = nil
        }
    }

    /// Gets the encoded target info data.
    ///
    /// - Returns: The encoded target info, or nil if not present.
    public func getEncodedTargetInfo() -> Data? {
        targetInfo?.encode(unicode: flags.contains(.negotiateUnicode))
    }

    /// Encodes the message to binary data.
    ///
    /// - Note: Challenge messages are typically only decoded from server responses,
    ///   but this method is provided for protocol conformance and testing.
    public func encode() -> Data {
        let encoding: String.Encoding = flags.contains(.negotiateUnicode) ? .utf16LittleEndian : .utf8
        let targetNameBytes = targetName?.data(using: encoding) ?? Data()
        let targetInfoBytes = getEncodedTargetInfo() ?? Data()

        var targetNameOffset = 48
        var targetInfoOffset = 56

        if !targetNameBytes.isEmpty {
            targetInfoOffset += targetNameBytes.count
        }

        var size = 48
        if flags.contains(.negotiateVersion) {
            size = 56
            targetNameOffset = 56
            targetInfoOffset = 56 + targetNameBytes.count
        }

        if !targetNameBytes.isEmpty || !targetInfoBytes.isEmpty {
            size = max(size, targetNameOffset + targetNameBytes.count + targetInfoBytes.count)
            if !targetInfoBytes.isEmpty {
                size = max(size, 48)
            }
        }

        var message = NtlmMessageUtils.prepareMessage(size: size + targetNameBytes.count + targetInfoBytes.count, type: 2)

        // Target name security buffer (at offset 12)
        if !targetNameBytes.isEmpty {
            message.writeUInt16LE(UInt16(targetNameBytes.count), at: 12)
            message.writeUInt16LE(UInt16(targetNameBytes.count), at: 14)
            message.writeUInt32LE(UInt32(targetNameOffset), at: 16)
        }

        // Flags (at offset 20)
        message.writeUInt32LE(flags.rawValue, at: 20)

        // Server challenge (8 bytes at offset 24)
        for (i, byte) in serverChallenge.enumerated() where i < 8 {
            message[24 + i] = byte
        }

        // Target info security buffer (at offset 40)
        if !targetInfoBytes.isEmpty {
            message.writeUInt16LE(UInt16(targetInfoBytes.count), at: 40)
            message.writeUInt16LE(UInt16(targetInfoBytes.count), at: 42)
            message.writeUInt32LE(UInt32(targetInfoOffset), at: 44)
        }

        // Version (at offset 48)
        if let osVersion = osVersion {
            message[48] = UInt8(osVersion.major)
            message[49] = UInt8(osVersion.minor)
            message.writeUInt16LE(UInt16(osVersion.build), at: 50)
            message[52] = 0x00
            message[53] = 0x00
            message[54] = 0x00
            message[55] = 0x0F
        }

        // Target name payload
        if !targetNameBytes.isEmpty {
            for (i, byte) in targetNameBytes.enumerated() {
                message[targetNameOffset + i] = byte
            }
        }

        // Target info payload
        if !targetInfoBytes.isEmpty {
            for (i, byte) in targetInfoBytes.enumerated() {
                message[targetInfoOffset + i] = byte
            }
        }

        return message
    }
}
