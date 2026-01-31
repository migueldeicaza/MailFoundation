//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

//
// ScramContext.swift
//
// SCRAM authentication context.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The hash algorithm variant for SCRAM authentication.
public enum ScramHashAlgorithm: Sendable {
    /// SCRAM-SHA-1 (RFC 5802)
    case sha1
    /// SCRAM-SHA-256 (RFC 7677)
    case sha256
    /// SCRAM-SHA-512
    case sha512

    /// The SASL mechanism name for this algorithm.
    public var mechanismName: String {
        switch self {
        case .sha1: return "SCRAM-SHA-1"
        case .sha256: return "SCRAM-SHA-256"
        case .sha512: return "SCRAM-SHA-512"
        }
    }
}

/// Channel binding data for SCRAM-PLUS mechanisms.
public struct ScramChannelBinding: Sendable, Equatable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public static func tlsUnique(_ data: Data) -> ScramChannelBinding {
        ScramChannelBinding(name: "tls-unique", data: data)
    }

    public static func tlsServerEndPoint(_ data: Data) -> ScramChannelBinding {
        ScramChannelBinding(name: "tls-server-end-point", data: data)
    }
}

/// A SCRAM (Salted Challenge Response Authentication Mechanism) context.
///
/// SCRAM provides a challenge-response authentication mechanism that:
/// - Never sends the password in cleartext
/// - Uses salted password hashing (PBKDF2)
/// - Provides mutual authentication (server proves it knows the password too)
///
/// ## Supported Variants
///
/// - SCRAM-SHA-1 (RFC 5802)
/// - SCRAM-SHA-256 (RFC 7677)
/// - SCRAM-SHA-512
///
/// ## Protocol Flow
///
/// 1. Client sends initial message with username and client nonce
/// 2. Server responds with salt, iteration count, and combined nonce
/// 3. Client computes salted password and sends proof
/// 4. Server responds with its signature for verification
///
/// ## Example
///
/// ```swift
/// let context = ScramContext(
///     username: "user",
///     password: "pencil",
///     algorithm: .sha256
/// )
///
/// // Get initial message
/// let initial = try context.getInitialMessage()
///
/// // Process server challenge
/// let response = try context.processChallenge(serverChallenge)
///
/// // Verify server signature
/// try context.verifyServerSignature(serverFinal)
/// ```
public final class ScramContext: @unchecked Sendable {
    /// The authentication state.
    private enum State {
        case initial
        case final
        case validate
        case complete
    }

    /// The hash algorithm to use.
    public let algorithm: ScramHashAlgorithm

    /// The username.
    public let username: String

    /// The password.
    private let password: String

    /// The optional authorization identity.
    public let authorizationId: String?

    /// Optional channel binding data for SCRAM-PLUS.
    private let channelBinding: ScramChannelBinding?

    /// Whether authentication has completed successfully.
    public private(set) var isAuthenticated = false

    /// The client nonce (can be set for testing).
    internal var cnonce: String?

    // Internal state
    private var state: State = .initial
    private var clientFirstMessageBare: String?
    private var serverFirstMessage: String?
    private var saltedPassword: Data?
    private var authMessage: Data?
    private var gs2Header: String?

    /// Creates a new SCRAM context.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The password.
    ///   - algorithm: The hash algorithm variant.
    ///   - authorizationId: Optional authorization identity.
    public init(
        username: String,
        password: String,
        algorithm: ScramHashAlgorithm,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) {
        self.username = username
        self.password = password
        self.algorithm = algorithm
        self.authorizationId = authorizationId
        self.channelBinding = channelBinding
    }

    /// Gets the SASL mechanism name.
    public var mechanismName: String {
        algorithm.mechanismName
    }

    /// Resets the context for reuse.
    public func reset() {
        state = .initial
        isAuthenticated = false
        clientFirstMessageBare = nil
        serverFirstMessage = nil
        saltedPassword = nil
        authMessage = nil
        cnonce = nil
        gs2Header = nil
    }

    /// Gets the initial client message (client-first-message).
    ///
    /// This is the first message sent by the client to start authentication.
    ///
    /// - Returns: The client-first-message as raw bytes.
    /// - Throws: `ScramError.alreadyAuthenticated` if already authenticated.
    public func getInitialMessage() throws -> Data {
        guard state == .initial else {
            throw ScramError.alreadyAuthenticated
        }

        // Generate client nonce if not set
        if cnonce == nil {
            cnonce = generateEntropy(18)
        }

        // Build client-first-message-bare: n=username,r=cnonce
        let normalizedUsername = normalize(username)
        clientFirstMessageBare = "n=\(normalizedUsername),r=\(cnonce!)"

        let header = buildGs2Header()
        gs2Header = header

        let message = header + clientFirstMessageBare!
        state = .final

        return Data(message.utf8)
    }

    /// Processes the server's first challenge.
    ///
    /// - Parameter challenge: The server's challenge (server-first-message).
    /// - Returns: The client's response (client-final-message).
    /// - Throws: `ScramError` if the challenge is invalid.
    public func processChallenge(_ challenge: Data) throws -> Data {
        // Auto-start if we haven't sent initial message yet
        if state == .initial {
            _ = try getInitialMessage()
        }

        guard state == .final else {
            throw ScramError.alreadyAuthenticated
        }

        guard let serverMessage = String(data: challenge, encoding: .utf8) else {
            throw ScramError.invalidChallenge("Challenge is not valid UTF-8")
        }

        serverFirstMessage = serverMessage
        let tokens = parseServerChallenge(serverMessage)

        // Extract required fields
        guard let salt = tokens["s"] else {
            throw ScramError.incompleteChallenge("Challenge did not contain a salt")
        }
        guard let nonce = tokens["r"] else {
            throw ScramError.incompleteChallenge("Challenge did not contain a nonce")
        }
        guard let iterationsStr = tokens["i"], let iterations = Int(iterationsStr), iterations > 0 else {
            throw ScramError.incompleteChallenge("Challenge did not contain a valid iteration count")
        }

        // Verify nonce starts with our cnonce
        guard nonce.hasPrefix(cnonce!) else {
            throw ScramError.invalidChallenge("Challenge contained an invalid nonce")
        }

        // Decode salt
        guard let saltData = Data(base64Encoded: salt) else {
            throw ScramError.invalidChallenge("Challenge contained invalid base64 salt")
        }

        // Compute salted password using PBKDF2 (Hi function)
        let preparedPassword = saslPrep(password)
        saltedPassword = try hi(Data(preparedPassword.utf8), salt: saltData, iterations: iterations)

        let header = gs2Header ?? buildGs2Header()
        gs2Header = header
        var channelBindingInput = Data(header.utf8)
        if let channelBinding {
            channelBindingInput.append(channelBinding.data)
        }
        let channelBindingEncoded = channelBindingInput.base64EncodedString()

        // Build client-final-message-without-proof
        let withoutProof = "c=\(channelBindingEncoded),r=\(nonce)"

        // Build auth message: client-first-message-bare + "," + server-first-message + "," + client-final-message-without-proof
        let authMessageStr = "\(clientFirstMessageBare!),\(serverFirstMessage!),\(withoutProof)"
        authMessage = Data(authMessageStr.utf8)

        // Compute ClientKey = HMAC(SaltedPassword, "Client Key")
        let clientKey = try hmac(key: saltedPassword!, message: Data("Client Key".utf8))

        // Compute StoredKey = H(ClientKey)
        let storedKey = hash(clientKey)

        // Compute ClientSignature = HMAC(StoredKey, AuthMessage)
        let clientSignature = try hmac(key: storedKey, message: authMessage!)

        // Compute ClientProof = ClientKey XOR ClientSignature
        let clientProof = xor(clientKey, clientSignature)

        // Build final message with proof
        let finalMessage = "\(withoutProof),p=\(clientProof.base64EncodedString())"
        state = .validate

        return Data(finalMessage.utf8)
    }

    /// Verifies the server's final signature.
    ///
    /// - Parameter serverFinal: The server's final message.
    /// - Throws: `ScramError.incorrectHash` if the signature doesn't match.
    public func verifyServerSignature(_ serverFinal: Data) throws {
        guard state == .validate else {
            throw ScramError.invalidChallenge("Not in validation state")
        }

        guard let message = String(data: serverFinal, encoding: .utf8) else {
            throw ScramError.invalidChallenge("Server final message is not valid UTF-8")
        }

        // Server sends: v=signature
        guard message.hasPrefix("v=") else {
            throw ScramError.invalidChallenge("Challenge did not start with a signature")
        }

        let signatureBase64 = String(message.dropFirst(2))
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw ScramError.invalidChallenge("Server signature is not valid base64")
        }

        // Compute expected ServerKey = HMAC(SaltedPassword, "Server Key")
        let serverKey = try hmac(key: saltedPassword!, message: Data("Server Key".utf8))

        // Compute expected ServerSignature = HMAC(ServerKey, AuthMessage)
        let expected = try hmac(key: serverKey, message: authMessage!)

        // Verify length
        guard signature.count == expected.count else {
            throw ScramError.incorrectHash("Challenge contained a signature with an invalid length")
        }

        // Constant-time comparison
        var match = true
        for i in 0..<signature.count {
            if signature[i] != expected[i] {
                match = false
            }
        }

        guard match else {
            throw ScramError.incorrectHash("Challenge contained an invalid signature. Expected: \(expected.base64EncodedString())")
        }

        isAuthenticated = true
        state = .complete
    }

    // MARK: - Cryptographic Primitives

    /// Computes HMAC with the algorithm-specific hash function.
    private func hmac(key: Data, message: Data) throws -> Data {
        #if canImport(CryptoKit)
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey)
            return Data(mac)
        case .sha256:
            let mac = HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey)
            return Data(mac)
        case .sha512:
            let mac = HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey)
            return Data(mac)
        }
        #else
        throw ScramError.cryptoUnavailable
        #endif
    }

    /// Computes hash with the algorithm-specific hash function.
    private func hash(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        switch algorithm {
        case .sha1:
            return Data(Insecure.SHA1.hash(data: data))
        case .sha256:
            return Data(SHA256.hash(data: data))
        case .sha512:
            return Data(SHA512.hash(data: data))
        }
        #else
        fatalError("CryptoKit is required for SCRAM")
        #endif
    }

    /// Hi function (PBKDF2 with HMAC).
    ///
    /// Hi(str, salt, i) = U1 XOR U2 XOR ... XOR Ui
    /// where:
    /// - U1 = HMAC(str, salt + INT(1))
    /// - U2 = HMAC(str, U1)
    /// - ...
    /// - Ui = HMAC(str, Ui-1)
    private func hi(_ str: Data, salt: Data, iterations: Int) throws -> Data {
        // First iteration: U1 = HMAC(str, salt || INT(1))
        var saltWithOne = salt
        saltWithOne.append(contentsOf: [0, 0, 0, 1])

        var u = try hmac(key: str, message: saltWithOne)
        var result = u

        // Remaining iterations
        for _ in 1..<iterations {
            u = try hmac(key: str, message: u)
            result = xor(result, u)
        }

        return result
    }

    /// XOR two data buffers.
    private func xor(_ a: Data, _ b: Data) -> Data {
        var result = a
        for i in 0..<min(a.count, b.count) {
            result[i] = a[i] ^ b[i]
        }
        return result
    }

    // MARK: - String Processing

    /// Parses a server challenge into key-value pairs.
    private func parseServerChallenge(_ challenge: String) -> [Character: String] {
        var results: [Character: String] = [:]
        for pair in challenge.split(separator: ",") {
            let pairStr = String(pair)
            guard pairStr.count >= 2, pairStr[pairStr.index(pairStr.startIndex, offsetBy: 1)] == "=" else {
                continue
            }
            let key = pairStr[pairStr.startIndex]
            let value = String(pairStr.dropFirst(2))
            results[key] = value
        }
        return results
    }

    /// Normalizes a username for SCRAM (escapes = and ,).
    private func normalize(_ str: String) -> String {
        let prepared = saslPrep(str)
        var result = ""
        for char in prepared {
            switch char {
            case ",":
                result += "=2C"
            case "=":
                result += "=3D"
            default:
                result.append(char)
            }
        }
        return result
    }

    /// Prepares authzid for the GS2 header.
    private func saslPrepAuthzId(_ authzid: String?) -> String {
        guard let authzid = authzid, !authzid.isEmpty else {
            return ""
        }
        return "a=" + normalize(authzid)
    }

    private func buildGs2Header() -> String {
        let authz = saslPrepAuthzId(authorizationId)
        let cbFlag: String
        if let channelBinding {
            cbFlag = "p=\(channelBinding.name)"
        } else {
            cbFlag = "n"
        }

        if authz.isEmpty {
            return "\(cbFlag),,"
        }
        return "\(cbFlag),\(authz),"
    }

    /// SASLprep string preparation (RFC 4013).
    private func saslPrep(_ str: String) -> String {
        var result = ""
        for scalar in str.unicodeScalars {
            if isNonAsciiSpace(scalar) {
                result.append(" ")
            } else if isCommonlyMappedToNothing(scalar) {
                // Skip
            } else if isControlCharacter(scalar) || isProhibited(scalar) {
                // Skip prohibited characters
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    /// Checks if the scalar is a control character.
    private func isControlCharacter(_ scalar: Unicode.Scalar) -> Bool {
        // Control characters are U+0000-U+001F and U+007F-U+009F
        let value = scalar.value
        return (value <= 0x001F) || (value >= 0x007F && value <= 0x009F)
    }

    /// Checks if the scalar is a non-ASCII space character.
    private func isNonAsciiSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00A0, // NO-BREAK SPACE
             0x1680, // OGHAM SPACE MARK
             0x2000...0x200B, // Various spaces
             0x202F, // NARROW NO-BREAK SPACE
             0x205F, // MEDIUM MATHEMATICAL SPACE
             0x3000: // IDEOGRAPHIC SPACE
            return true
        default:
            return false
        }
    }

    /// Checks if the scalar is commonly mapped to nothing.
    private func isCommonlyMappedToNothing(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x034F, 0x1806,
             0x180B...0x180D,
             0x200B...0x200D,
             0x2060,
             0xFE00...0xFE0F,
             0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Checks if the scalar is prohibited.
    private func isProhibited(_ scalar: Unicode.Scalar) -> Bool {
        let u = scalar.value

        // Private Use
        if (u >= 0xE000 && u <= 0xF8FF) ||
            (u >= 0xF0000 && u <= 0xFFFFD) ||
            (u >= 0x100000 && u <= 0x10FFFD) {
            return true
        }

        // Non-character code points
        if (u >= 0xFDD0 && u <= 0xFDEF) ||
            (u >= 0xFFFE && u <= 0xFFFF) {
            return true
        }

        // Surrogate code points
        if u >= 0xD800 && u <= 0xDFFF {
            return true
        }

        return false
    }

    /// Generates random entropy for the client nonce.
    private func generateEntropy(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
