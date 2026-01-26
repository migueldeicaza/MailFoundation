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

/// Factory methods for creating SASL authentication configurations for IMAP.
///
/// `ImapSasl` provides static methods for creating ``ImapAuthentication``
/// configurations for various SASL mechanisms supported by IMAP servers.
///
/// ## Supported Mechanisms
///
/// - `PLAIN` - Simple username/password in a single base64-encoded string
/// - `LOGIN` - Challenge-response with separate username and password prompts
/// - `NTLM` - Microsoft NTLM challenge-response authentication (NTLMv2)
/// - `XOAUTH2` - OAuth 2.0 bearer token authentication
///
/// ## Security Considerations
///
/// - `PLAIN` sends credentials in base64 (not encrypted) - use only over TLS
/// - `LOGIN` is similar to PLAIN but uses challenge-response
/// - `NTLM` never sends the password but uses legacy cryptography
/// - `XOAUTH2` is recommended for services that support OAuth
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

    /// Chooses the best available authentication mechanism.
    ///
    /// This method selects the most secure mechanism that is both supported
    /// by the server and available on this platform. The preference order is:
    /// 1. NTLM (for Exchange servers)
    /// 2. PLAIN
    /// 3. LOGIN
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The user's password.
    ///   - mechanisms: The mechanisms supported by the server.
    /// - Returns: An ``ImapAuthentication`` for the best available mechanism, or nil if none match.
    public static func chooseAuthentication(
        username: String,
        password: String,
        mechanisms: [String]
    ) -> ImapAuthentication? {
        let normalized = mechanisms.map { $0.uppercased() }
        if normalized.contains("NTLM") {
            return ntlm(username: username, password: password)
        }
        if normalized.contains("PLAIN") {
            return plain(username: username, password: password)
        }
        if normalized.contains("LOGIN") {
            return login(username: username, password: password)
        }
        return nil
    }
}
