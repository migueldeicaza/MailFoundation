//
// NtlmAttribute.swift
//
// NTLM target info attribute types.
//
// Port of MailKit's NtlmAttribute.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// Target info attribute types used in NTLM AV_PAIR structures.
///
/// These attributes are used in the Target Information block of NTLM Challenge
/// messages (Type 2) and are used in computing the NTLMv2 response.
public enum NtlmAttribute: Int16, Sendable {
    /// End of list marker.
    case eol = 0

    /// The server's NetBIOS computer name.
    case serverName = 1

    /// The server's NetBIOS domain name.
    case domainName = 2

    /// The fully qualified domain name (FQDN) of the server.
    case dnsServerName = 3

    /// The fully qualified domain name (FQDN) of the domain.
    case dnsDomainName = 4

    /// The fully qualified domain name (FQDN) of the forest.
    case dnsTreeName = 5

    /// A 32-bit value indicating server or client configuration flags.
    case flags = 6

    /// A FILETIME timestamp containing the server local time.
    case timestamp = 7

    /// Single host data structure.
    case singleHost = 8

    /// The Service Principal Name (SPN) of the server.
    case targetName = 9

    /// The channel binding hash (MD5 of channel binding data).
    case channelBinding = 10
}
