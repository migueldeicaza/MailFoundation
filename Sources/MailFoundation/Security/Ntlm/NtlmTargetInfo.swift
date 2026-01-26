//
// NtlmTargetInfo.swift
//
// NTLM Target Information parsing and encoding.
//
// Port of MailKit's NtlmTargetInfo.cs and NtlmAttributeValuePair.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// Represents an NTLM Target Information block.
///
/// The Target Information block contains AV_PAIR structures that provide
/// server information used in NTLMv2 response computation.
public struct NtlmTargetInfo: Sendable {
    /// The server's NetBIOS computer name.
    public var serverName: String?

    /// The server's NetBIOS domain name.
    public var domainName: String?

    /// The fully qualified domain name (FQDN) of the server.
    public var dnsServerName: String?

    /// The fully qualified domain name (FQDN) of the domain.
    public var dnsDomainName: String?

    /// The fully qualified domain name (FQDN) of the forest.
    public var dnsTreeName: String?

    /// Server or client configuration flags.
    public var flags: Int32?

    /// A timestamp containing the server local time (FILETIME format).
    public var timestamp: Int64?

    /// Single host data structure.
    public var singleHost: Data?

    /// The Service Principal Name (SPN) of the server.
    public var targetName: String?

    /// The channel binding hash (MD5 of channel binding data).
    public var channelBinding: Data?

    /// Unknown attributes preserved during parsing.
    private var unknownAttributes: [(NtlmAttribute, Data)] = []

    /// Creates an empty target info structure.
    public init() {}

    /// Creates a target info structure by decoding binary data.
    ///
    /// - Parameters:
    ///   - data: The binary data to decode.
    ///   - unicode: Whether strings are Unicode (UTF-16LE) or OEM (UTF-8).
    /// - Throws: An error if decoding fails.
    public init(data: Data, unicode: Bool) throws {
        try decode(data: data, unicode: unicode)
    }

    // MARK: - Decoding

    private mutating func decode(data: Data, unicode: Bool) throws {
        let encoding: String.Encoding = unicode ? .utf16LittleEndian : .utf8
        var index = 0

        while index + 4 <= data.count {
            let attrRaw = data.readInt16LE(at: index)
            let length = Int(data.readUInt16LE(at: index + 2))
            index += 4

            guard index + length <= data.count else { break }

            guard let attr = NtlmAttribute(rawValue: attrRaw) else {
                // Unknown attribute - preserve it
                let value = data.subdata(in: index..<(index + length))
                unknownAttributes.append((NtlmAttribute(rawValue: attrRaw) ?? .eol, value))
                index += length
                continue
            }

            switch attr {
            case .eol:
                return

            case .serverName:
                serverName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .domainName:
                domainName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .dnsServerName:
                dnsServerName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .dnsDomainName:
                dnsDomainName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .dnsTreeName:
                dnsTreeName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .targetName:
                targetName = decodeString(data: data, at: index, length: length, encoding: encoding)

            case .flags:
                switch length {
                case 4: flags = data.readInt32LE(at: index)
                case 2: flags = Int32(data.readInt16LE(at: index))
                default: flags = 0
                }

            case .timestamp:
                switch length {
                case 8: timestamp = data.readInt64LE(at: index)
                case 4: timestamp = Int64(data.readUInt32LE(at: index))
                case 2: timestamp = Int64(data.readUInt16LE(at: index))
                default: timestamp = 0
                }

            case .singleHost:
                singleHost = data.subdata(in: index..<(index + length))

            case .channelBinding:
                channelBinding = data.subdata(in: index..<(index + length))
            }

            index += length
        }
    }

    private func decodeString(data: Data, at index: Int, length: Int, encoding: String.Encoding) -> String? {
        guard length > 0, index + length <= data.count else { return nil }
        let subdata = data.subdata(in: index..<(index + length))
        return String(data: subdata, encoding: encoding)
    }

    // MARK: - Encoding

    /// Encodes the target info to binary data.
    ///
    /// - Parameter unicode: Whether to encode strings as Unicode (UTF-16LE) or OEM (UTF-8).
    /// - Returns: The encoded target info.
    public func encode(unicode: Bool) -> Data {
        let encoding: String.Encoding = unicode ? .utf16LittleEndian : .utf8
        var data = Data()

        // Encode known attributes
        encodeString(&data, attr: .serverName, value: serverName, encoding: encoding)
        encodeString(&data, attr: .domainName, value: domainName, encoding: encoding)
        encodeString(&data, attr: .dnsServerName, value: dnsServerName, encoding: encoding)
        encodeString(&data, attr: .dnsDomainName, value: dnsDomainName, encoding: encoding)
        encodeString(&data, attr: .dnsTreeName, value: dnsTreeName, encoding: encoding)
        encodeString(&data, attr: .targetName, value: targetName, encoding: encoding)

        if let flags = flags {
            encodeFlags(&data, flags: flags)
        }

        if let timestamp = timestamp {
            encodeTimestamp(&data, timestamp: timestamp)
        }

        if let singleHost = singleHost {
            encodeBytes(&data, attr: .singleHost, value: singleHost)
        }

        if let channelBinding = channelBinding {
            encodeBytes(&data, attr: .channelBinding, value: channelBinding)
        }

        // Encode unknown attributes
        for (attr, value) in unknownAttributes {
            encodeBytes(&data, attr: attr, value: value)
        }

        // End of list marker
        data.appendInt16LE(NtlmAttribute.eol.rawValue)
        data.appendInt16LE(0)

        return data
    }

    private func encodeString(_ data: inout Data, attr: NtlmAttribute, value: String?, encoding: String.Encoding) {
        guard let value = value, let encoded = value.data(using: encoding) else { return }
        data.appendInt16LE(attr.rawValue)
        data.appendInt16LE(Int16(encoded.count))
        data.append(encoded)
    }

    private func encodeFlags(_ data: inout Data, flags: Int32) {
        data.appendInt16LE(NtlmAttribute.flags.rawValue)
        data.appendInt16LE(4)
        data.appendInt32LE(flags)
    }

    private func encodeTimestamp(_ data: inout Data, timestamp: Int64) {
        data.appendInt16LE(NtlmAttribute.timestamp.rawValue)
        data.appendInt16LE(8)
        data.appendInt64LE(timestamp)
    }

    private func encodeBytes(_ data: inout Data, attr: NtlmAttribute, value: Data) {
        data.appendInt16LE(attr.rawValue)
        data.appendInt16LE(Int16(value.count))
        data.append(value)
    }

    // MARK: - Copying

    /// Creates a copy of this target info.
    public func copy() -> NtlmTargetInfo {
        var copy = NtlmTargetInfo()
        copy.serverName = serverName
        copy.domainName = domainName
        copy.dnsServerName = dnsServerName
        copy.dnsDomainName = dnsDomainName
        copy.dnsTreeName = dnsTreeName
        copy.flags = flags
        copy.timestamp = timestamp
        copy.singleHost = singleHost
        copy.targetName = targetName
        copy.channelBinding = channelBinding
        copy.unknownAttributes = unknownAttributes
        return copy
    }
}
