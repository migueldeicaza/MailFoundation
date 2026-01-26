//
// NtlmFlags.swift
//
// NTLM negotiation flags.
//
// Port of MailKit's NtlmFlags.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// NTLM message header negotiation flags.
///
/// These flags control various aspects of NTLM authentication negotiation
/// between client and server.
public struct NtlmFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Indicates that Unicode strings are supported for use in security buffer data.
    public static let negotiateUnicode = NtlmFlags(rawValue: 0x0000_0001)

    /// Indicates that OEM strings are supported for use in security buffer data.
    public static let negotiateOem = NtlmFlags(rawValue: 0x0000_0002)

    /// Requests that the server's authentication realm be included in the Type 2 message.
    public static let requestTarget = NtlmFlags(rawValue: 0x0000_0004)

    /// Specifies that authenticated communication should carry a digital signature (message integrity).
    public static let negotiateSign = NtlmFlags(rawValue: 0x0000_0010)

    /// Specifies that authenticated communication should be encrypted (message confidentiality).
    public static let negotiateSeal = NtlmFlags(rawValue: 0x0000_0020)

    /// Indicates that datagram authentication is being used.
    public static let negotiateDatagramStyle = NtlmFlags(rawValue: 0x0000_0040)

    /// Indicates that the Lan Manager Session Key should be used for signing and sealing.
    public static let negotiateLanManagerKey = NtlmFlags(rawValue: 0x0000_0080)

    /// Indicates that NTLM authentication is being used.
    public static let negotiateNtlm = NtlmFlags(rawValue: 0x0000_0200)

    /// Sent by the client in the Type 3 message to indicate that an anonymous context has been established.
    public static let negotiateAnonymous = NtlmFlags(rawValue: 0x0000_0800)

    /// Sent by the client in the Type 1 message to indicate that the domain name is included.
    public static let negotiateDomainSupplied = NtlmFlags(rawValue: 0x0000_1000)

    /// Sent by the client in the Type 1 message to indicate that the workstation name is included.
    public static let negotiateWorkstationSupplied = NtlmFlags(rawValue: 0x0000_2000)

    /// Sent by the server to indicate that server and client are on the same machine.
    public static let negotiateLocalCall = NtlmFlags(rawValue: 0x0000_4000)

    /// Indicates that authenticated communication should be signed with a "dummy" signature.
    public static let negotiateAlwaysSign = NtlmFlags(rawValue: 0x0000_8000)

    /// Sent by the server in Type 2 to indicate that the target authentication realm is a domain.
    public static let targetTypeDomain = NtlmFlags(rawValue: 0x0001_0000)

    /// Sent by the server in Type 2 to indicate that the target authentication realm is a server.
    public static let targetTypeServer = NtlmFlags(rawValue: 0x0002_0000)

    /// Sent by the server in Type 2 to indicate that the target authentication realm is a share.
    public static let targetTypeShare = NtlmFlags(rawValue: 0x0004_0000)

    /// Requests usage of NTLM v2 session security (extended session security).
    ///
    /// This is mutually exclusive with `negotiateLanManagerKey`. If both are requested,
    /// only `negotiateExtendedSessionSecurity` is returned.
    public static let negotiateExtendedSessionSecurity = NtlmFlags(rawValue: 0x0008_0000)

    /// Identifies the connection.
    public static let negotiateIdentify = NtlmFlags(rawValue: 0x0010_0000)

    /// Indicates that the LMOWF function should be used to generate a session key.
    public static let requestNonNTSessionKey = NtlmFlags(rawValue: 0x0040_0000)

    /// Sent by the server in Type 2 to indicate that it includes a Target Information block.
    public static let negotiateTargetInfo = NtlmFlags(rawValue: 0x0080_0000)

    /// Indicates that the version field is present.
    public static let negotiateVersion = NtlmFlags(rawValue: 0x0200_0000)

    /// Indicates that 128-bit encryption is supported.
    public static let negotiate128 = NtlmFlags(rawValue: 0x2000_0000)

    /// Indicates that the client will provide an encrypted master key in the "Session Key" field.
    public static let negotiateKeyExchange = NtlmFlags(rawValue: 0x4000_0000)

    /// Indicates that 56-bit encryption is supported.
    public static let negotiate56 = NtlmFlags(rawValue: 0x8000_0000)

    /// Default flags used when creating a negotiate message.
    ///
    /// This matches the flags typically used by System.Net.Mail and other NTLM implementations.
    public static let defaultNegotiate: NtlmFlags = [
        .negotiate56,
        .negotiateUnicode,
        .negotiateOem,
        .requestTarget,
        .negotiateNtlm,
        .negotiateAlwaysSign,
        .negotiateExtendedSessionSecurity,
        .negotiate128,
    ]
}
