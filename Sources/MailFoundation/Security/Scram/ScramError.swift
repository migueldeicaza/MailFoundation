//
// ScramError.swift
//
// SCRAM authentication errors.
//

import Foundation

/// Errors that can occur during SCRAM authentication.
///
/// SCRAM (Salted Challenge Response Authentication Mechanism) is a
/// challenge-response authentication protocol defined in RFC 5802.
public enum ScramError: Error, Sendable, Equatable, LocalizedError {
    /// The server's challenge is missing required fields.
    case incompleteChallenge(String)

    /// The server's challenge contains invalid data.
    case invalidChallenge(String)

    /// The server's signature does not match the expected value.
    case incorrectHash(String)

    /// The input data is not valid base64.
    case invalidBase64

    /// The required cryptographic functions are not available.
    case cryptoUnavailable

    /// The SCRAM context has already completed authentication.
    case alreadyAuthenticated

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .incompleteChallenge(let detail):
            return "Incomplete SCRAM challenge: \(detail)"
        case .invalidChallenge(let detail):
            return "Invalid SCRAM challenge: \(detail)"
        case .incorrectHash(let detail):
            return "Incorrect SCRAM hash: \(detail)"
        case .invalidBase64:
            return "Invalid base64 encoding in SCRAM challenge"
        case .cryptoUnavailable:
            return "Required cryptographic functions are not available"
        case .alreadyAuthenticated:
            return "SCRAM authentication has already completed"
        }
    }
}
