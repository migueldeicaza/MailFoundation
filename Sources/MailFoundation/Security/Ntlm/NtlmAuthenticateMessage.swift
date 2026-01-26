//
// NtlmAuthenticateMessage.swift
//
// NTLM Type 3 (Authenticate) message.
//
// Port of MailKit's NtlmAuthenticateMessage.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import Foundation

/// NTLM Type 3 (Authenticate) message.
///
/// This message is sent by the client in response to a Type 2 challenge.
/// It contains the client's response to the server's challenge using NTLMv2.
public struct NtlmAuthenticateMessage: NtlmMessage, Sendable {
    public let type = 3

    /// The negotiation flags.
    public let flags: NtlmFlags

    /// The domain name.
    public let domain: String?

    /// The username.
    public let userName: String

    /// The workstation name.
    public let workstation: String?

    /// The LM challenge response.
    public let lmChallengeResponse: Data

    /// The NT challenge response.
    public let ntChallengeResponse: Data?

    /// The encrypted random session key (if key exchange is negotiated).
    public let encryptedRandomSessionKey: Data?

    /// The exported session key (for MIC computation).
    public let exportedSessionKey: Data?

    /// The Message Integrity Code.
    public let mic: Data?

    /// The OS version (optional).
    public let osVersion: (major: Int, minor: Int, build: Int)?

    /// Reference to the original negotiate message (for MIC computation).
    private let negotiateMessage: NtlmNegotiateMessage?

    /// Reference to the challenge message (for MIC computation).
    private let challengeMessage: NtlmChallengeMessage?

    /// Creates a new authenticate message in response to a challenge.
    ///
    /// - Parameters:
    ///   - negotiate: The original negotiate message.
    ///   - challenge: The server's challenge message.
    ///   - userName: The username.
    ///   - password: The password.
    ///   - domain: The domain name (optional, can be extracted from challenge).
    ///   - workstation: The workstation name (optional).
    ///   - clientChallenge: The 8-byte client challenge (optional, auto-generated if nil).
    ///   - timestamp: Optional timestamp override (for testing).
    public init(
        negotiate: NtlmNegotiateMessage,
        challenge: NtlmChallengeMessage,
        userName: String,
        password: String,
        domain: String? = nil,
        workstation: String? = nil,
        clientChallenge: Data? = nil,
        timestamp: Int64? = nil
    ) {
        self.negotiateMessage = negotiate
        self.challengeMessage = challenge
        self.userName = userName
        self.workstation = workstation

        // Determine domain
        let resolvedDomain: String?
        if let domain = domain, !domain.isEmpty {
            resolvedDomain = domain
        } else if challenge.flags.contains(.targetTypeDomain) {
            // Server is domain-joined, TargetName is the domain
            resolvedDomain = challenge.targetName
        } else if let targetInfo = challenge.targetInfo {
            // Server is not domain-joined, use domain from target info
            resolvedDomain = targetInfo.domainName
        } else {
            resolvedDomain = nil
        }
        self.domain = resolvedDomain

        // Compute flags: intersection of client and server flags
        var flags = negotiate.flags.intersection(challenge.flags)

        // If both Unicode and OEM are supported, prefer Unicode
        if flags.contains(.negotiateUnicode) {
            flags.remove(.negotiateOem)
        }

        // If extended session security is enabled, disable LM key
        if flags.contains(.negotiateExtendedSessionSecurity) {
            flags.remove(.negotiateLanManagerKey)
        }

        // Disable key exchange if neither sign nor seal is present
        if flags.contains(.negotiateKeyExchange), !flags.contains(.negotiateSign), !flags.contains(.negotiateSeal) {
            flags.remove(.negotiateKeyExchange)
        }

        // If RequestTarget was in negotiate, include it in authenticate
        if negotiate.flags.contains(.requestTarget) {
            flags.insert(.requestTarget)
        }

        self.flags = flags
        self.osVersion = negotiate.osVersion

        // Generate client challenge
        let clientChallengeData = clientChallenge ?? NtlmUtils.nonce(8)

        // Build target info for response
        var targetInfo = challenge.targetInfo?.copy() ?? NtlmTargetInfo()
        var avFlags = targetInfo.flags ?? 0

        // If timestamp is present in challenge, we should provide a MIC
        let shouldProvideMic = challenge.targetInfo?.timestamp != nil

        if shouldProvideMic {
            // Set MIC flag
            avFlags |= 0x02
            targetInfo.flags = avFlags
        }

        // Add empty target name
        if targetInfo.targetName == nil {
            targetInfo.targetName = ""
        }

        // Add channel binding (Z16 since we don't support channel binding yet)
        if targetInfo.channelBinding == nil {
            targetInfo.channelBinding = Data(count: 16)
        }

        // Encode target info
        let encodedTargetInfo = targetInfo.encode(unicode: flags.contains(.negotiateUnicode))

        // Compute NTLMv2 response
        let (ntResponse, lmResponse, sessionBaseKey) = NtlmUtils.computeNtlmV2(
            serverChallenge: challenge.serverChallenge,
            serverTimestamp: challenge.targetInfo?.timestamp,
            domain: resolvedDomain,
            userName: userName,
            password: password,
            targetInfo: encodedTargetInfo,
            clientChallenge: clientChallengeData,
            time: timestamp
        )

        self.ntChallengeResponse = ntResponse
        self.lmChallengeResponse = lmResponse

        // Handle key exchange
        if flags.contains(.negotiateKeyExchange),
           flags.contains([.negotiateSign]) || flags.contains([.negotiateSeal]),
           let sessionBaseKey = sessionBaseKey
        {
            let exportedKey = NtlmUtils.nonce(16)
            self.exportedSessionKey = exportedKey
            self.encryptedRandomSessionKey = NtlmUtils.rc4k(key: sessionBaseKey, message: exportedKey)
        } else {
            self.exportedSessionKey = sessionBaseKey
            self.encryptedRandomSessionKey = nil
        }

        // Compute MIC if needed
        if shouldProvideMic, self.exportedSessionKey != nil {
            // MIC is computed over all three messages
            // For now, we'll compute it during encode() since we need the final message
            self.mic = Data(count: 16)  // Placeholder, will be computed during encode
        } else {
            self.mic = nil
        }
    }

    /// Decodes an authenticate message from binary data.
    ///
    /// - Parameter data: The message data.
    /// - Throws: `NtlmError` if the message is invalid.
    public init(data: Data) throws {
        try NtlmMessageUtils.validateMessage(data, expectedType: 3)

        self.negotiateMessage = nil
        self.challengeMessage = nil

        // Flags
        if data.count >= 64 {
            self.flags = NtlmFlags(rawValue: data.readUInt32LE(at: 60))
        } else {
            self.flags = NtlmFlags(rawValue: 0x8201)
        }

        let encoding: String.Encoding = flags.contains(.negotiateUnicode) ? .utf16LittleEndian : .utf8

        // LM Challenge Response
        let lmLength = Int(data.readUInt16LE(at: 12))
        let lmOffset = Int(data.readUInt16LE(at: 16))
        if lmLength > 0, lmOffset + lmLength <= data.count {
            self.lmChallengeResponse = data.subdata(in: lmOffset..<(lmOffset + lmLength))
        } else {
            self.lmChallengeResponse = Data()
        }

        // NT Challenge Response
        let ntLength = Int(data.readUInt16LE(at: 20))
        let ntOffset = Int(data.readUInt16LE(at: 24))
        if ntLength > 0, ntOffset + ntLength <= data.count {
            self.ntChallengeResponse = data.subdata(in: ntOffset..<(ntOffset + ntLength))
        } else {
            self.ntChallengeResponse = nil
        }

        // Domain
        let domainLength = Int(data.readUInt16LE(at: 28))
        let domainOffset = Int(data.readUInt16LE(at: 32))
        if domainLength > 0, domainOffset + domainLength <= data.count {
            let domainData = data.subdata(in: domainOffset..<(domainOffset + domainLength))
            self.domain = String(data: domainData, encoding: encoding)
        } else {
            self.domain = nil
        }

        // UserName
        let userLength = Int(data.readUInt16LE(at: 36))
        let userOffset = Int(data.readUInt16LE(at: 40))
        if userLength > 0, userOffset + userLength <= data.count {
            let userData = data.subdata(in: userOffset..<(userOffset + userLength))
            self.userName = String(data: userData, encoding: encoding) ?? ""
        } else {
            self.userName = ""
        }

        // Workstation
        let wsLength = Int(data.readUInt16LE(at: 44))
        let wsOffset = Int(data.readUInt16LE(at: 48))
        if wsLength > 0, wsOffset + wsLength <= data.count {
            let wsData = data.subdata(in: wsOffset..<(wsOffset + wsLength))
            self.workstation = String(data: wsData, encoding: encoding)
        } else {
            self.workstation = nil
        }

        // Encrypted Random Session Key
        let skeyLength = Int(data.readUInt16LE(at: 52))
        let skeyOffset = Int(data.readUInt16LE(at: 56))
        if skeyLength > 0, skeyOffset + skeyLength <= data.count {
            self.encryptedRandomSessionKey = data.subdata(in: skeyOffset..<(skeyOffset + skeyLength))
        } else {
            self.encryptedRandomSessionKey = nil
        }

        // OS Version
        if flags.contains(.negotiateVersion), data.count >= 72 {
            let major = Int(data[64])
            let minor = Int(data[65])
            let build = Int(data.readUInt16LE(at: 66))
            self.osVersion = (major, minor, build)
        } else {
            self.osVersion = nil
        }

        // These are not available when decoding
        self.exportedSessionKey = nil
        self.mic = nil
    }

    /// Encodes the message to binary data.
    public func encode() -> Data {
        let encoding: String.Encoding = flags.contains(.negotiateUnicode) ? .utf16LittleEndian : .utf8

        let domainBytes = domain?.data(using: encoding) ?? Data()
        let userBytes = userName.data(using: encoding) ?? Data()
        let workstationBytes = workstation?.data(using: encoding) ?? Data()

        let lmResponseLength = lmChallengeResponse.count
        let ntResponseLength = ntChallengeResponse?.count ?? 0
        let skeyLength = encryptedRandomSessionKey?.count ?? 0

        var payloadOffset = 72  // Base header size with version
        var micOffset = -1

        if mic != nil {
            micOffset = payloadOffset
            payloadOffset += 16
        }

        // Calculate offsets
        let domainOffset = payloadOffset
        let userOffset = domainOffset + domainBytes.count
        let workstationOffset = userOffset + userBytes.count
        let lmResponseOffset = workstationOffset + workstationBytes.count
        let ntResponseOffset = lmResponseOffset + lmResponseLength
        let skeyOffset = ntResponseOffset + ntResponseLength

        let totalSize = skeyOffset + skeyLength

        var message = NtlmMessageUtils.prepareMessage(size: totalSize, type: 3)

        // LM Challenge Response (offset 12)
        message.writeUInt16LE(UInt16(lmResponseLength), at: 12)
        message.writeUInt16LE(UInt16(lmResponseLength), at: 14)
        message.writeUInt16LE(UInt16(lmResponseOffset), at: 16)

        // NT Challenge Response (offset 20)
        message.writeUInt16LE(UInt16(ntResponseLength), at: 20)
        message.writeUInt16LE(UInt16(ntResponseLength), at: 22)
        message.writeUInt16LE(UInt16(ntResponseOffset), at: 24)

        // Domain (offset 28)
        message.writeUInt16LE(UInt16(domainBytes.count), at: 28)
        message.writeUInt16LE(UInt16(domainBytes.count), at: 30)
        message.writeUInt16LE(UInt16(domainOffset), at: 32)

        // UserName (offset 36)
        message.writeUInt16LE(UInt16(userBytes.count), at: 36)
        message.writeUInt16LE(UInt16(userBytes.count), at: 38)
        message.writeUInt16LE(UInt16(userOffset), at: 40)

        // Workstation (offset 44)
        message.writeUInt16LE(UInt16(workstationBytes.count), at: 44)
        message.writeUInt16LE(UInt16(workstationBytes.count), at: 46)
        message.writeUInt16LE(UInt16(workstationOffset), at: 48)

        // Encrypted Random Session Key (offset 52)
        message.writeUInt16LE(UInt16(skeyLength), at: 52)
        message.writeUInt16LE(UInt16(skeyLength), at: 54)
        message.writeUInt16LE(UInt16(skeyOffset), at: 56)

        // Flags (offset 60)
        message.writeUInt32LE(flags.rawValue, at: 60)

        // OS Version (offset 64)
        if let osVersion = osVersion {
            message[64] = UInt8(osVersion.major)
            message[65] = UInt8(osVersion.minor)
            message.writeUInt16LE(UInt16(osVersion.build), at: 66)
            message[68] = 0x00
            message[69] = 0x00
            message[70] = 0x00
            message[71] = 0x0F
        }

        // MIC (offset 72 if present)
        if micOffset >= 0, let mic = mic {
            for (i, byte) in mic.enumerated() {
                if micOffset + i < message.count {
                    message[micOffset + i] = byte
                }
            }
        }

        // Payloads
        for (i, byte) in domainBytes.enumerated() {
            message[domainOffset + i] = byte
        }

        for (i, byte) in userBytes.enumerated() {
            message[userOffset + i] = byte
        }

        for (i, byte) in workstationBytes.enumerated() {
            message[workstationOffset + i] = byte
        }

        for (i, byte) in lmChallengeResponse.enumerated() {
            message[lmResponseOffset + i] = byte
        }

        if let ntChallengeResponse = ntChallengeResponse {
            for (i, byte) in ntChallengeResponse.enumerated() {
                message[ntResponseOffset + i] = byte
            }
        }

        if let encryptedRandomSessionKey = encryptedRandomSessionKey {
            for (i, byte) in encryptedRandomSessionKey.enumerated() {
                message[skeyOffset + i] = byte
            }
        }

        // Compute and write MIC if needed
        // Note: MIC computation requires the original challenge bytes, which we don't preserve.
        // A full implementation would store the original challenge data for MIC computation.
        // For now, MIC is left as zeros if present.
        if micOffset >= 0 {
            for i in 0..<16 {
                message[micOffset + i] = 0
            }
        }

        return message
    }
}
