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
// SmtpSasl.swift
//
// SASL helpers for SMTP AUTH.
//

import Foundation

public struct SmtpAuthentication: Sendable {
    public let mechanism: String
    public let initialResponse: String?
    public let responder: (@Sendable (String) throws -> String)?

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

public enum SmtpSasl {
    public static func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    public static func plain(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> SmtpAuthentication {
        let authz = authorizationId ?? ""
        let payload = "\(authz)\u{0}\(username)\u{0}\(password)"
        return SmtpAuthentication(
            mechanism: "PLAIN",
            initialResponse: base64(payload)
        )
    }

    public static func login(
        username: String,
        password: String,
        useInitialResponse: Bool = false
    ) -> SmtpAuthentication {
        let initial = useInitialResponse ? base64(username) : nil
        let responder: @Sendable (String) throws -> String = { challenge in
            let trimmed = challenge.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: trimmed),
               let text = String(data: data, encoding: .utf8) {
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
        return SmtpAuthentication(
            mechanism: "LOGIN",
            initialResponse: initial,
            responder: responder
        )
    }

    public static func xoauth2(username: String, accessToken: String) -> SmtpAuthentication {
        let payload = "user=\(username)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return SmtpAuthentication(
            mechanism: "XOAUTH2",
            initialResponse: base64(payload)
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
    /// - Returns: A ``SmtpAuthentication`` configured for SCRAM-SHA-1.
    public static func scramSha1(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> SmtpAuthentication {
        scram(
            username: username,
            password: password,
            algorithm: .sha1,
            authorizationId: authorizationId
        )
    }

    /// Creates a SCRAM-SHA-1-PLUS SASL authentication configuration.
    public static func scramSha1Plus(
        username: String,
        password: String,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding
    ) -> SmtpAuthentication {
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
    /// - Returns: A ``SmtpAuthentication`` configured for SCRAM-SHA-256.
    public static func scramSha256(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> SmtpAuthentication {
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
    ) -> SmtpAuthentication {
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
    /// - Returns: A ``SmtpAuthentication`` configured for SCRAM-SHA-512.
    public static func scramSha512(
        username: String,
        password: String,
        authorizationId: String? = nil
    ) -> SmtpAuthentication {
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
    ) -> SmtpAuthentication {
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
    /// - Returns: A ``SmtpAuthentication`` configured for the specified SCRAM variant.
    public static func scram(
        username: String,
        password: String,
        algorithm: ScramHashAlgorithm,
        authorizationId: String? = nil,
        channelBinding: ScramChannelBinding? = nil,
        usePlus: Bool = false
    ) -> SmtpAuthentication {
        let state = SmtpScramSaslState(
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
        return SmtpAuthentication(
            mechanism: mechanism,
            initialResponse: initialResponse,
            responder: responder
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
    /// - Returns: A ``SmtpAuthentication`` configured for NTLM.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let auth = SmtpSasl.ntlm(
    ///     username: "CORP\\jsmith",
    ///     password: "secret"
    /// )
    /// ```
    public static func ntlm(
        username: String,
        password: String,
        domain: String? = nil,
        workstation: String? = nil
    ) -> SmtpAuthentication {
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

        return SmtpAuthentication(
            mechanism: "NTLM",
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
    ///   - servicePrincipalName: The SPN (e.g., "smtp/mail.example.com"). If nil, defaults to "smtp/{host}".
    ///   - host: The server hostname (used to build default SPN).
    ///   - username: Optional username for credential acquisition.
    ///   - password: Optional password for credential acquisition.
    /// - Returns: A ``SmtpAuthentication`` configured for GSSAPI, or nil if GSSAPI is unavailable.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let auth = SmtpSasl.gssapi(host: "mail.example.com")
    /// // Uses default Kerberos credentials from credential cache
    /// ```
    public static func gssapi(
        servicePrincipalName: String? = nil,
        host: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) -> SmtpAuthentication? {
        guard GssapiContext.isAvailable else { return nil }

        let spn = servicePrincipalName ?? (host.map { "smtp@\($0)" } ?? "smtp")
        let state = SmtpGssapiSaslState(
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

        return SmtpAuthentication(
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
    /// 5. NTLM
    /// 6. PLAIN
    /// 7. LOGIN
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - mechanisms: The mechanisms supported by the server.
    ///   - host: Optional server hostname for GSSAPI SPN.
    /// - Returns: A ``SmtpAuthentication`` for the best available mechanism, or nil if none match.
    public static func chooseAuthentication(
        username: String,
        password: String,
        mechanisms: [String],
        host: String? = nil,
        channelBinding: ScramChannelBinding? = nil
    ) -> SmtpAuthentication? {
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

/// Internal state holder for SMTP SCRAM SASL authentication.
final class SmtpScramSaslState: @unchecked Sendable {
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
            let response = try context.processChallenge(challengeData)
            challengePhase = false
            return response.base64EncodedString()
        } else {
            try context.verifyServerSignature(challengeData)
            return ""
        }
    }
}

/// Internal state holder for SMTP GSSAPI SASL authentication.
final class SmtpGssapiSaslState: @unchecked Sendable {
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
            let response = try context.initSecContext(inputToken: challengeData)
            if context.isComplete {
                authComplete = true
            }
            return response.base64EncodedString()
        } else {
            let response = try context.negotiateSecurityLayer(challenge: challengeData)
            return response.base64EncodedString()
        }
    }
}
