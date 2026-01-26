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
}
