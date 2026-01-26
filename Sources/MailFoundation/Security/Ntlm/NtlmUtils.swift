//
// NtlmUtils.swift
//
// NTLM utility functions for NTLMv2 computation.
//
// Port of MailKit's NtlmUtils.cs
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/b38c36ed-2804-4868-a9ff-8dd3182128e4
//

import CryptoKit
import Foundation

/// Utility functions for NTLM authentication.
public enum NtlmUtils {
    /// Response version for NTLMv2.
    private static let responserversion: [UInt8] = [1]

    /// Hi response version for NTLMv2.
    private static let hiResponserversion: [UInt8] = [1]

    /// 24 zero bytes.
    private static let z24 = Data(count: 24)

    /// 6 zero bytes.
    private static let z6 = Data(count: 6)

    /// 4 zero bytes.
    private static let z4 = Data(count: 4)

    /// 1 zero byte.
    private static let z1 = Data(count: 1)

    // MARK: - Username Parsing

    /// Parses a username into user and domain components.
    ///
    /// Supports formats:
    /// - `DOMAIN\user` (backslash separator)
    /// - `user@domain` (at-sign separator)
    /// - `user` (no domain)
    ///
    /// - Parameters:
    ///   - username: The username to parse.
    ///   - domain: An optional domain to use if none is found in the username.
    /// - Returns: A tuple of (username, domain).
    public static func parseUsername(_ username: String, domain: String? = nil) -> (user: String, domain: String?) {
        // Check for DOMAIN\user format
        if let backslashIndex = username.firstIndex(of: "\\") {
            let domainPart = String(username[..<backslashIndex])
            let userPart = String(username[username.index(after: backslashIndex)...])
            return (userPart, domainPart)
        }

        // Check for user@domain format
        if let atIndex = username.firstIndex(of: "@") {
            let userPart = String(username[..<atIndex])
            let domainPart = String(username[username.index(after: atIndex)...])
            return (userPart, domainPart)
        }

        // No domain in username
        return (username, domain)
    }

    // MARK: - Cryptographic Functions

    /// Computes HMAC-MD5 of the given data using the specified key.
    ///
    /// - Parameters:
    ///   - key: The HMAC key.
    ///   - data: The data to authenticate.
    /// - Returns: The 16-byte HMAC-MD5 result.
    public static func hmacMd5(key: Data, data: Data) -> Data {
        let hmac = HMAC<Insecure.MD5>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    /// Computes HMAC-MD5 of multiple data segments using the specified key.
    ///
    /// - Parameters:
    ///   - key: The HMAC key.
    ///   - values: The data segments to authenticate.
    /// - Returns: The 16-byte HMAC-MD5 result.
    public static func hmacMd5(key: Data, values: [Data]) -> Data {
        var hmac = HMAC<Insecure.MD5>(key: SymmetricKey(data: key))
        for value in values {
            hmac.update(data: value)
        }
        return Data(hmac.finalize())
    }

    /// Computes MD5 hash of the given data.
    ///
    /// - Parameter data: The data to hash.
    /// - Returns: The 16-byte MD5 hash.
    public static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    /// Generates cryptographically random bytes.
    ///
    /// - Parameter count: The number of bytes to generate.
    /// - Returns: Random bytes.
    public static func nonce(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Encrypts data using RC4 with the given key.
    ///
    /// - Parameters:
    ///   - key: The RC4 key.
    ///   - message: The message to encrypt.
    /// - Returns: The encrypted message.
    public static func rc4k(key: Data, message: Data) -> Data {
        RC4.transform(key: key, message: message)
    }

    // MARK: - NTLMv2 Response Computation

    /// Computes the NTOWFv2 (NT One-Way Function v2) for password hashing.
    ///
    /// - Parameters:
    ///   - domain: The domain name.
    ///   - userName: The username.
    ///   - password: The password.
    /// - Returns: The NTLMv2 response key.
    private static func ntowfv2(domain: String?, userName: String, password: String) -> Data {
        // MD4(UNICODE(password))
        let md4 = MD4()
        let passwordData = password.data(using: .utf16LittleEndian) ?? Data()
        let hash = md4.computeHash(passwordData)

        // HMAC_MD5(hash, UNICODE(UPPERCASE(userName) + domain))
        let userDom = (userName.uppercased() + (domain ?? "")).data(using: .utf16LittleEndian) ?? Data()
        return hmacMd5(key: hash, data: userDom)
    }

    /// Computes the NTLMv2 challenge response.
    ///
    /// - Parameters:
    ///   - serverChallenge: The 8-byte server challenge from the Type 2 message.
    ///   - serverTimestamp: Optional timestamp from server's target info.
    ///   - domain: The domain name.
    ///   - userName: The username.
    ///   - password: The password.
    ///   - targetInfo: The encoded target info from the server.
    ///   - clientChallenge: The 8-byte client challenge.
    ///   - time: Optional timestamp override (for testing).
    /// - Returns: A tuple of (ntChallengeResponse, lmChallengeResponse, sessionBaseKey).
    public static func computeNtlmV2(
        serverChallenge: Data,
        serverTimestamp: Int64?,
        domain: String?,
        userName: String,
        password: String,
        targetInfo: Data,
        clientChallenge: Data,
        time: Int64? = nil
    ) -> (ntChallengeResponse: Data?, lmChallengeResponse: Data, sessionBaseKey: Data?) {
        // Special case for anonymous authentication
        if userName.isEmpty && password.isEmpty {
            return (nil, z1, nil)
        }

        // Compute timestamp
        // Windows FILETIME: 100-nanosecond intervals since January 1, 1601
        // Swift Date: seconds since January 1, 2001
        // Offset from Unix epoch (1970) to Windows epoch (1601): 11644473600 seconds
        // Offset from Unix epoch (1970) to Swift epoch (2001): -978307200 seconds
        let windowsEpochOffset: Int64 = 116_444_736_000_000_000  // 100ns intervals from 1601 to 1970
        var timestamp: Int64

        if let serverTimestamp = serverTimestamp {
            // Use server timestamp if available
            timestamp = serverTimestamp
        } else if let time = time {
            // Use provided time for testing
            timestamp = time
        } else {
            // Convert current time to Windows FILETIME
            let unixTime = Int64(Date().timeIntervalSince1970 * 10_000_000)  // 100ns intervals since 1970
            timestamp = unixTime + windowsEpochOffset
        }

        let responseKey = ntowfv2(domain: domain, userName: userName, password: password)

        // Build temp: Responserversion || HiResponserversion || Z(6) || Time || ClientChallenge || Z(4) || ServerName || Z(4)
        var temp = Data()
        temp.append(contentsOf: responserversion)
        temp.append(contentsOf: hiResponserversion)
        temp.append(z6)
        temp.appendInt64LE(timestamp)
        temp.append(clientChallenge)
        temp.append(z4)
        temp.append(targetInfo)
        temp.append(z4)

        // NTProofStr = HMAC_MD5(ResponseKeyNT, ServerChallenge || temp)
        let proof = hmacMd5(key: responseKey, values: [serverChallenge, temp])

        // SessionBaseKey = HMAC_MD5(ResponseKeyNT, NTProofStr)
        let sessionBaseKey = hmacMd5(key: responseKey, data: proof)

        // NtChallengeResponse = NTProofStr || temp
        var ntChallengeResponse = proof
        ntChallengeResponse.append(temp)

        // LmChallengeResponse
        let lmChallengeResponse: Data
        if serverTimestamp == nil {
            // Set LmChallengeResponse = HMAC_MD5(ResponseKeyLM, ServerChallenge || ClientChallenge) || ClientChallenge
            let hash = hmacMd5(key: responseKey, values: [serverChallenge, clientChallenge])
            var response = hash
            response.append(clientChallenge)
            lmChallengeResponse = response
        } else {
            // If timestamp present, send Z(24) instead
            lmChallengeResponse = z24
        }

        return (ntChallengeResponse, lmChallengeResponse, sessionBaseKey)
    }
}
