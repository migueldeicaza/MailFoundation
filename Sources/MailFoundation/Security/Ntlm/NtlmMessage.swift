//
// NtlmMessage.swift
//
// NTLM message protocol and utilities.
//
// Port of MailKit's NtlmMessageBase.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// The NTLM message signature "NTLMSSP\0".
public let ntlmSignature: [UInt8] = [
    0x4E, 0x54, 0x4C, 0x4D, 0x53, 0x53, 0x50, 0x00,  // "NTLMSSP\0"
]

/// Protocol for NTLM messages.
public protocol NtlmMessage: Sendable {
    /// The message type (1 = Negotiate, 2 = Challenge, 3 = Authenticate).
    var type: Int { get }

    /// The negotiation flags.
    var flags: NtlmFlags { get }

    /// Encodes the message to binary data.
    func encode() -> Data
}

/// Errors that can occur during NTLM message processing.
public enum NtlmError: Error, Sendable, Equatable {
    /// The message data is too short.
    case messageTooShort

    /// The message signature is invalid (not "NTLMSSP\0").
    case invalidSignature

    /// The message type does not match the expected type.
    case invalidMessageType(expected: Int, actual: Int)

    /// The base64 data could not be decoded.
    case invalidBase64

    /// A required parameter is missing.
    case missingParameter(String)
}

// MARK: - Data Extensions for Little-Endian Encoding

extension Data {
    /// Reads a little-endian UInt16 from the specified offset.
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    /// Reads a little-endian Int16 from the specified offset.
    func readInt16LE(at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16LE(at: offset))
    }

    /// Reads a little-endian UInt32 from the specified offset.
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    /// Reads a little-endian Int32 from the specified offset.
    func readInt32LE(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(at: offset))
    }

    /// Reads a little-endian Int64 from the specified offset.
    func readInt64LE(at offset: Int) -> Int64 {
        guard offset + 8 <= count else { return 0 }
        let lo = UInt64(readUInt32LE(at: offset))
        let hi = UInt64(readUInt32LE(at: offset + 4))
        return Int64(bitPattern: (hi << 32) | lo)
    }

    /// Creates a new Data by appending a little-endian UInt16.
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    /// Creates a new Data by appending a little-endian Int16.
    mutating func appendInt16LE(_ value: Int16) {
        appendUInt16LE(UInt16(bitPattern: value))
    }

    /// Creates a new Data by appending a little-endian UInt32.
    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    /// Creates a new Data by appending a little-endian Int32.
    mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }

    /// Creates a new Data by appending a little-endian Int64.
    mutating func appendInt64LE(_ value: Int64) {
        let unsigned = UInt64(bitPattern: value)
        appendUInt32LE(UInt32(unsigned & 0xFFFF_FFFF))
        appendUInt32LE(UInt32(unsigned >> 32))
    }

    /// Writes a little-endian UInt16 at the specified offset.
    mutating func writeUInt16LE(_ value: UInt16, at offset: Int) {
        guard offset + 2 <= count else { return }
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    /// Writes a little-endian UInt32 at the specified offset.
    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        guard offset + 4 <= count else { return }
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
        self[offset + 2] = UInt8((value >> 16) & 0xFF)
        self[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

// MARK: - Message Base Utilities

/// Utility functions for NTLM message encoding/decoding.
public enum NtlmMessageUtils {
    /// Prepares a message buffer with the NTLM signature and message type.
    ///
    /// - Parameters:
    ///   - size: The total size of the message buffer.
    ///   - type: The message type (1, 2, or 3).
    /// - Returns: A data buffer with the signature and type pre-filled.
    public static func prepareMessage(size: Int, type: Int) -> Data {
        var data = Data(count: size)
        // Copy signature
        for (i, byte) in ntlmSignature.enumerated() {
            data[i] = byte
        }
        // Write message type as little-endian UInt32
        data.writeUInt32LE(UInt32(type), at: 8)
        return data
    }

    /// Validates an NTLM message signature and type.
    ///
    /// - Parameters:
    ///   - data: The message data to validate.
    ///   - expectedType: The expected message type.
    /// - Throws: `NtlmError` if validation fails.
    public static func validateMessage(_ data: Data, expectedType: Int) throws {
        guard data.count >= 12 else {
            throw NtlmError.messageTooShort
        }

        // Check signature
        for (i, byte) in ntlmSignature.enumerated() {
            guard data[i] == byte else {
                throw NtlmError.invalidSignature
            }
        }

        // Check message type
        let actualType = Int(data.readUInt32LE(at: 8))
        guard actualType == expectedType else {
            throw NtlmError.invalidMessageType(expected: expectedType, actual: actualType)
        }
    }
}
