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
// ImapSasl.swift
//
// SASL helpers for IMAP AUTHENTICATE.
//

import Foundation

/// Represents a SASL authentication mechanism configuration for IMAP.
///
/// This struct encapsulates everything needed to perform SASL authentication
/// with an IMAP server, including the mechanism name, optional initial response,
/// and a responder for challenge-response mechanisms.
///
/// ## Usage
///
/// For simple mechanisms like PLAIN:
///
/// ```swift
/// let auth = ImapSasl.plain(username: "user", password: "secret")
/// // auth.mechanism is "PLAIN"
/// // auth.initialResponse contains the base64-encoded credentials
/// ```
///
/// For challenge-response mechanisms like NTLM:
///
/// ```swift
/// let auth = ImapSasl.ntlm(username: "DOMAIN\\user", password: "secret")
/// // auth.responder handles server challenges
/// ```
public struct ImapAuthentication: Sendable {
    /// The SASL mechanism name (e.g., "PLAIN", "LOGIN", "NTLM", "XOAUTH2").
    public let mechanism: String

    /// The optional initial response for mechanisms that support it.
    ///
    /// This is base64-encoded data sent with the AUTHENTICATE command for mechanisms
    /// that don't require a server challenge first.
    public let initialResponse: String?

    /// A closure that generates responses to server challenges.
    ///
    /// For challenge-response mechanisms, this closure is called with each
    /// challenge from the server and should return the appropriate response.
    public let responder: (@Sendable (String) throws -> String)?

    /// Initializes a new authentication configuration.
    ///
    /// - Parameters:
    ///   - mechanism: The SASL mechanism name.
    ///   - initialResponse: Optional base64-encoded initial response.
    ///   - responder: Optional closure for handling server challenges.
    public init(
        mechanism: String,
        initialResponse: String? = nil,
        responder: (@Sendable (String) throws -> String)? = nil
    ) {
        self.mechanism = mechanism
        self.initialResponse = initialResponse
        self.responder = responder
    }
}

// MARK: - Adapter

extension ImapAuthentication {
    /// Creates an IMAP authentication configuration from a unified SASL mechanism.
    ///
    /// - Parameter mechanism: The SASL mechanism to adapt.
    public init(mechanism: SaslMechanism) {
        self.mechanism = mechanism.name

        var initial: String? = nil
        if mechanism.supportsInitialResponse {
            if let data = try? mechanism.initialResponse() {
                initial = Data(data).base64EncodedString()
            }
        }
        self.initialResponse = initial

        self.responder = { challengeBase64 in
            let trimmed = challengeBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            let challengeData: [UInt8]
            if trimmed.isEmpty || trimmed == "+" {
                challengeData = []
            } else if let data = Data(base64Encoded: trimmed) {
                challengeData = Array(data)
            } else {
                challengeData = Array(trimmed.utf8)
            }

            let responseBytes = try mechanism.challenge(challengeData)
            return Data(responseBytes).base64EncodedString()
        }
    }
}

/// Factory methods for creating SASL authentication configurations for IMAP.
///
/// `ImapSasl` provides static methods for creating ``ImapAuthentication``
/// configurations for various SASL mechanisms supported by IMAP servers.
///
/// ## Supported Mechanisms
///
/// - `SCRAM-SHA-512` - Salted challenge-response with SHA-512
/// - `SCRAM-SHA-256` - Salted challenge-response with SHA-256
/// - `SCRAM-SHA-1` - Salted challenge-response with SHA-1
/// - `PLAIN` - Simple username/password in a single base64-encoded string
/// - `LOGIN` - Challenge-response with separate username and password prompts
/// - `NTLM` - Microsoft NTLM challenge-response authentication (NTLMv2)
/// - `CRAM-MD5` - Challenge-response using HMAC-MD5 (requires CryptoKit)
/// - `DIGEST-MD5` - Digest challenge-response (requires CryptoKit)
/// - `XOAUTH2` - OAuth 2.0 bearer token authentication
/// - `OAUTHBEARER` - OAuth 2.0 bearer token authentication (RFC 7628)
/// - `EXTERNAL` - External authentication (TLS client certs, etc.)
///
/// ## Security Considerations
///
/// - `SCRAM-*` mechanisms are recommended - password is never sent, only hashes
/// - `PLAIN` sends credentials in base64 (not encrypted) - use only over TLS
/// - `LOGIN` is similar to PLAIN but uses challenge-response
/// - `NTLM` never sends the password but uses legacy cryptography
/// - `XOAUTH2`/`OAUTHBEARER` are recommended for services that support OAuth
/// - `EXTERNAL` is used when the server authenticates via external mechanisms (e.g., TLS client certs)
public enum ImapSasl {
    /// Encodes a string as base64.
    ///
    /// - Parameter text: The string to encode.
    /// - Returns: The base64-encoded string.
    public static func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Creates a PLAIN SASL authentication configuration.
    ///
    /// PLAIN authentication sends credentials as: `authzid\0username\0password`
    /// encoded in base64. This should only be used over TLS connections.
    ///
    /// - Parameters:
    ///   - username: The username (authentication identity).
    ///   - password: The user's password.
    ///   - authorizationId: Optional authorization identity (usually empty).
    /// - Returns: An ``ImapAuthentication`` configured for PLAIN.
    public static func plain(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> ImapAuthentication {
        let authz = authorizationId ?? ""
        let payload = "\(authz)\u{0}\(username)\u{0}\(password)"
        return ImapAuthentication(
            mechanism: "PLAIN",
            initialResponse: base64(payload)
        )
    }

    /// Creates a LOGIN SASL authentication configuration.
    ///
    /// LOGIN is a legacy mechanism that prompts for username and password
    /// separately. Like PLAIN, it should only be used over TLS.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - useInitialResponse: Whether to send username as initial response.
    /// - Returns: An ``ImapAuthentication`` configured for LOGIN.
    public static func login(
        username: String,
        password: String,
        useInitialResponse: Bool = false
    ) -> ImapAuthentication {
        let initial = useInitialResponse ? base64(username) : nil
        let responder: @Sendable (String) throws -> String = { challenge in
            let trimmed = challenge.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: trimmed),
               let text = String(data: data, encoding: .utf8)
            {
                let lower = text.lowercased()
                if lower.contains("username") {
                    return base64(username)
                }
                if lower.contains("password") {
                    return base64(password)
                }
            }
            if trimmed.isEmpty {
                return base64(username)
            }
            return base64(password)
        }
        return ImapAuthentication(
            mechanism: "LOGIN",
            initialResponse: initial,
            responder: responder
        )
    }

    /// Creates an XOAUTH2 SASL authentication configuration.
    ///
    /// XOAUTH2 is used for OAuth 2.0 authentication with services like Gmail
    /// and Outlook.com. You must obtain an access token from the OAuth provider
    /// before using this method.
    ///
    /// - Parameters:
    ///   - username: The username or email address.
    ///   - accessToken: The OAuth 2.0 access token.
    /// - Returns: An ``ImapAuthentication`` configured for XOAUTH2.
    public static func xoauth2(username: String, accessToken: String) -> ImapAuthentication {
        let payload = "user=\(username)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return ImapAuthentication(
            mechanism: "XOAUTH2",
            initialResponse: base64(payload)
        )
    }

    /// Creates an OAUTHBEARER SASL authentication configuration.
    ///
    /// OAUTHBEARER is similar to XOAUTH2 but supports additional parameters
    /// like host and port (RFC 7628).
    ///
    /// - Parameters:
    ///   - username: The username or email address.
    ///   - accessToken: The OAuth 2.0 access token.
    ///   - host: Optional host name for the server.
    ///   - port: Optional port number.
    ///   - authorizationId: Optional authorization identity override.
    /// - Returns: An ``ImapAuthentication`` configured for OAUTHBEARER.
    public static func oauthBearer(
        username: String,
        accessToken: String,
        host: String? = nil,
        port: Int? = nil,
        authorizationId: String? = nil
    ) -> ImapAuthentication {
        ImapAuthentication(
            mechanism: OAuthBearerSaslMechanism(
                username: username,
                accessToken: accessToken,
                host: host,
                port: port,
                authorizationId: authorizationId
            )
        )
    }

    /// Creates an EXTERNAL SASL authentication configuration.
    ///
    /// - Parameter authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for EXTERNAL.
    public static func external(authorizationId: String? = nil) -> ImapAuthentication {
        ImapAuthentication(mechanism: ExternalSaslMechanism(authorizationId: authorizationId))
    }

    /// Creates a CRAM-MD5 SASL authentication configuration.
    ///
    /// CRAM-MD5 uses challenge-response authentication where the password
    /// is never sent over the network. Requires CryptoKit.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    /// - Returns: An ``ImapAuthentication`` configured for CRAM-MD5, or nil if unavailable.
    public static func cramMd5(
        username: String,
        password: String
    ) -> ImapAuthentication? {
        guard hmacMd5Available else { return nil }
        return ImapAuthentication(mechanism: CramMd5SaslMechanism(username: username, password: password))
    }

    /// Creates a DIGEST-MD5 SASL authentication configuration.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - host: The server hostname.
    ///   - service: The service name (default: "imap").
    ///   - authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for DIGEST-MD5, or nil if unavailable.
    public static func digestMd5(
        username: String,
        password: String,
        host: String,
        service: String = "imap",
        authorizationId: String? = nil
    ) -> ImapAuthentication? {
        guard md5Available else { return nil }
        return ImapAuthentication(
            mechanism: DigestMd5SaslMechanism(
                username: username,
                password: password,
                host: host,
                service: service,
                authorizationId: authorizationId
            )
        )
    }

    /// Creates an NTLM SASL authentication configuration.
    ///
    /// NTLM is a challenge-response authentication mechanism commonly used
    /// with Microsoft Exchange servers. This implementation uses NTLMv2.
    ///
    /// - Parameters:
    ///   - username: The username (can include domain as `DOMAIN\\user` or `user@domain`).
    ///   - password: The user's password.
    ///   - domain: The domain name (optional if included in username).
    ///   - workstation: The workstation name (optional).
    /// - Returns: An ``ImapAuthentication`` configured for NTLM.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let auth = ImapSasl.ntlm(
    ///     username: "CORP\\jsmith",
    ///     password: "secret"
    /// )
    /// ```
    public static func ntlm(
        username: String,
        password: String,
        domain: String? = nil,
        workstation: String? = nil
    ) -> ImapAuthentication {
        let (user, resolvedDomain) = NtlmUtils.parseUsername(username, domain: domain)
        let negotiate = NtlmNegotiateMessage(domain: resolvedDomain, workstation: workstation)
        let initialResponse = negotiate.encode().base64EncodedString()

        let responder: @Sendable (String) throws -> String = { challengeBase64 in
            let trimmed = challengeBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let challengeData = Data(base64Encoded: trimmed) else {
                throw NtlmError.invalidBase64
            }
            let challenge = try NtlmChallengeMessage(data: challengeData)
            let authenticate = NtlmAuthenticateMessage(
                negotiate: negotiate,
                challenge: challenge,
                userName: user,
                password: password,
                domain: resolvedDomain,
                workstation: workstation
            )
            return authenticate.encode().base64EncodedString()
        }

        return ImapAuthentication(
            mechanism: "NTLM",
            initialResponse: initialResponse,
            responder: responder
        )
    }

    /// Creates a SCRAM-SHA-1 SASL authentication configuration.
    ///
    /// SCRAM-SHA-1 (RFC 5802) is a salted challenge-response mechanism that
    /// never sends the password over the network.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for SCRAM-SHA-1.
    public static func scramSha1(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha1,
            authorizationId: authorizationId
        )
    }

    /// Creates a SCRAM-SHA-1-PLUS SASL authentication configuration.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - authorizationId: Optional authorization identity.
    ///   - channelBinding: Channel binding data for SCRAM-PLUS.
    /// - Returns: An ``ImapAuthentication`` configured for SCRAM-SHA-1-PLUS.
    public static func scramSha1Plus(
        username: String,
        password: String,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha1,
            authorizationId: authorizationId,
            channelBinding: channelBinding,
            usePlus: true
        )
    }

    /// Creates a SCRAM-SHA-256 SASL authentication configuration.
    ///
    /// SCRAM-SHA-256 (RFC 7677) is a salted challenge-response mechanism that
    /// never sends the password over the network. This is stronger than SCRAM-SHA-1.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for SCRAM-SHA-256.
    public static func scramSha256(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha256,
            authorizationId: authorizationId
        )
    }

    /// Creates a SCRAM-SHA-256-PLUS SASL authentication configuration.
    public static func scramSha256Plus(
        username: String,
        password: String,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha256,
            authorizationId: authorizationId,
            channelBinding: channelBinding,
            usePlus: true
        )
    }

    /// Creates a SCRAM-SHA-512 SASL authentication configuration.
    ///
    /// SCRAM-SHA-512 is a salted challenge-response mechanism that
    /// never sends the password over the network. This is the strongest SCRAM variant.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for SCRAM-SHA-512.
    public static func scramSha512(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha512,
            authorizationId: authorizationId
        )
    }

    /// Creates a SCRAM-SHA-512-PLUS SASL authentication configuration.
    public static func scramSha512Plus(
        username: String,
        password: String,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding
    ) -> ImapAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha512,
            authorizationId: authorizationId,
            channelBinding: channelBinding,
            usePlus: true
        )
    }

    /// Creates a SCRAM SASL authentication configuration with the specified algorithm.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - algorithm: The hash algorithm to use.
    ///   - authorizationId: Optional authorization identity.
    /// - Returns: An ``ImapAuthentication`` configured for the specified SCRAM variant.
    public static func scram(
        username: String,
        password: String,
        algorithm: ScramHashAlgorithm,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding? = nil,
        usePlus: Bool = false
    ) -> ImapAuthentication {
        let state = ScramSaslState(
            username: username,
            password: password,
            algorithm: algorithm,
            authorizationId: authorizationId,
            channelBinding: channelBinding
        )

        // Generate initial message
        let initialResponse: String?
        do {
            let initial = try state.context.getInitialMessage()
            initialResponse = initial.base64EncodedString()
        } catch {
            initialResponse = nil
        }

        let responder: @Sendable (String) throws -> String = { challengeBase64 in
            try state.processChallenge(challengeBase64)
        }

        let mechanism = usePlus ? "\(algorithm.mechanismName)-PLUS" : algorithm.mechanismName
        return ImapAuthentication(
            mechanism: mechanism,
            initialResponse: initialResponse,
            responder: responder
        )
    }

    /// Creates a GSSAPI (Kerberos) SASL authentication configuration.
    ///
    /// GSSAPI provides Kerberos-based authentication, commonly used in
    /// enterprise environments with Active Directory.
    ///
    /// - Parameters:
    ///   - servicePrincipalName: The SPN (e.g., "imap/mail.example.com"). If nil, defaults to "imap/{host}".
    ///   - host: The server hostname (used to build default SPN).
    ///   - username: Optional username for credential acquisition.
    ///   - password: Optional password for credential acquisition.
    /// - Returns: An ``ImapAuthentication`` configured for GSSAPI, or nil if GSSAPI is unavailable.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let auth = ImapSasl.gssapi(host: "mail.example.com")
    /// // Uses default Kerberos credentials from credential cache
    /// ```
    public static func gssapi(
        servicePrincipalName: String? = nil,
        host: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) -> ImapAuthentication? {
        guard GssapiContext.isAvailable else { return nil }

        let spn = servicePrincipalName ?? (host.map { "imap@\($0)" } ?? "imap")
        let state = GssapiSaslState(
            servicePrincipalName: spn,
            username: username,
            password: password
        )

        // Generate initial token
        let initialToken: String?
        do {
            let token = try state.context.initSecContext(inputToken: nil)
            initialToken = token.isEmpty ? nil : token.base64EncodedString()
        } catch {
            return nil
        }

        let responder: @Sendable (String) throws -> String = { challengeBase64 in
            try state.processChallenge(challengeBase64)
        }

        return ImapAuthentication(
            mechanism: "GSSAPI",
            initialResponse: initialToken,
            responder: responder
        )
    }

    /// Chooses the best available authentication mechanism.
    ///
    /// This method selects the most secure mechanism that is both supported
    /// by the server and available on this platform. The preference order is:
    /// 1. SCRAM-SHA-512
    /// 2. SCRAM-SHA-256
    /// 3. SCRAM-SHA-1
    /// 4. GSSAPI (Kerberos, if available)
    /// 5. NTLM (for Exchange servers)
    /// 6. DIGEST-MD5 (if available)
    /// 7. CRAM-MD5 (if available)
    /// 8. PLAIN
    /// 9. LOGIN
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - mechanisms: The mechanisms supported by the server.
    ///   - host: Optional server hostname for GSSAPI SPN.
    /// - Returns: An ``ImapAuthentication`` for the best available mechanism, or nil if none match.
    public static func chooseAuthentication(
        username: String,
        password: String,
        mechanisms: [String],
        host: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) -> ImapAuthentication? {
        let normalized = mechanisms.map { $0.uppercased() }

        // SCRAM variants (strongest to weakest)
        if let channelBinding {
            if normalized.contains("SCRAM-SHA-512-PLUS") {
                return scramSha512Plus(username: username, password: password, authorizationId: nil, channelBinding: channelBinding)
            }
            if normalized.contains("SCRAM-SHA-256-PLUS") {
                return scramSha256Plus(username: username, password: password, authorizationId: nil, channelBinding: channelBinding)
            }
            if normalized.contains("SCRAM-SHA-1-PLUS") {
                return scramSha1Plus(username: username, password: password, authorizationId: nil, channelBinding: channelBinding)
            }
        }
        if normalized.contains("SCRAM-SHA-512") {
            return scramSha512(username: username, password: password)
        }
        if normalized.contains("SCRAM-SHA-256") {
            return scramSha256(username: username, password: password)
        }
        if normalized.contains("SCRAM-SHA-1") {
            return scramSha1(username: username, password: password)
        }

        // GSSAPI (Kerberos)
        if normalized.contains("GSSAPI"),
           let auth = gssapi(host: host, username: username, password: password)
        {
            return auth
        }

        // NTLM
        if normalized.contains("NTLM") {
            return ntlm(username: username, password: password)
        }

        // DIGEST-MD5
        if normalized.contains("DIGEST-MD5"),
           let host,
           let digest = digestMd5(username: username, password: password, host: host)
        {
            return digest
        }

        // CRAM-MD5
        if normalized.contains("CRAM-MD5"),
           let cram = cramMd5(username: username, password: password)
        {
            return cram
        }

        // Plain text (use only over TLS)
        if normalized.contains("PLAIN") {
            return plain(username: username, password: password)
        }
        if normalized.contains("LOGIN") {
            return login(username: username, password: password)
        }
        return nil
    }
}

private let hmacMd5Available: Bool = {
    #if canImport(CryptoKit)
    return true
    #else
    return false
    #endif
}()

private let md5Available: Bool = {
    #if canImport(CryptoKit)
    return true
    #else
    return false
    #endif
}()

/// Internal state holder for SCRAM SASL authentication.
final class ScramSaslState: @unchecked Sendable {
    let context: ScramContext
    private var challengePhase = true

    init(
        username: String,
        password: String,
        algorithm: ScramHashAlgorithm,
        authorizationId: String?,
        channelBinding: ScramChannelBinding? = nil
    ) {
        self.context = ScramContext(
            username: username,
            password: password,
            algorithm: algorithm,
            authorizationId: authorizationId,
            channelBinding: channelBinding
        )
    }

    func processChallenge(_ challengeBase64: String) throws -> String {
        let trimmed = challengeBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let challengeData = Data(base64Encoded: trimmed) else {
            throw ScramError.invalidBase64
        }

        if challengePhase {
            // Server first message - compute response
            let response = try context.processChallenge(challengeData)
            challengePhase = false
            return response.base64EncodedString()
        } else {
            // Server final message - verify signature
            try context.verifyServerSignature(challengeData)
            // Return empty response after verification
            return ""
        }
    }
}

/// Internal state holder for GSSAPI SASL authentication.
///
/// This class manages the stateful GSSAPI authentication flow.
final class GssapiSaslState: @unchecked Sendable {
    let context: GssapiContext
    private var authComplete = false

    init(servicePrincipalName: String, username: String?, password: String?) {
        self.context = GssapiContext(
            servicePrincipalName: servicePrincipalName,
            username: username,
            password: password
        )
    }

    func processChallenge(_ challengeBase64: String) throws -> String {
        let trimmed = challengeBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let challengeData = Data(base64Encoded: trimmed) else {
            throw GssapiError.invalidBase64
        }

        if !authComplete {
            // Continue authentication
            let response = try context.initSecContext(inputToken: challengeData)
            if context.isComplete {
                authComplete = true
            }
            return response.base64EncodedString()
        } else {
            // Security layer negotiation
            let response = try context.negotiateSecurityLayer(challenge: challengeData)
            return response.base64EncodedString()
        }
    }
}
