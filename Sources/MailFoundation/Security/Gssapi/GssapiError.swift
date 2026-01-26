//
// GssapiError.swift
//
// Errors for GSSAPI/Kerberos authentication.
//

import Foundation

/// Errors that can occur during GSSAPI/Kerberos authentication.
public enum GssapiError: Error, Sendable, Equatable {
    /// GSSAPI is not available on this platform.
    case notAvailable

    /// Failed to acquire credentials.
    case credentialAcquisitionFailed(String)

    /// Failed to initialize security context.
    case contextInitFailed(String)

    /// Invalid or malformed token received.
    case invalidToken

    /// Invalid base64-encoded data.
    case invalidBase64

    /// Security layer negotiation failed.
    case securityLayerNegotiationFailed

    /// The server does not support the required security layer.
    case securityLayerNotSupported

    /// Wrap/unwrap operation failed.
    case wrapFailed(String)

    /// The authentication is incomplete.
    case authenticationIncomplete

    /// Generic GSSAPI error with major and minor status codes.
    case gssError(major: UInt32, minor: UInt32, message: String)
}

extension GssapiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "GSSAPI is not available on this platform"
        case .credentialAcquisitionFailed(let message):
            return "Failed to acquire GSSAPI credentials: \(message)"
        case .contextInitFailed(let message):
            return "Failed to initialize GSSAPI context: \(message)"
        case .invalidToken:
            return "Invalid or malformed GSSAPI token"
        case .invalidBase64:
            return "Invalid base64-encoded data"
        case .securityLayerNegotiationFailed:
            return "Security layer negotiation failed"
        case .securityLayerNotSupported:
            return "Server does not support required security layer"
        case .wrapFailed(let message):
            return "GSSAPI wrap operation failed: \(message)"
        case .authenticationIncomplete:
            return "GSSAPI authentication is incomplete"
        case .gssError(let major, let minor, let message):
            return "GSSAPI error (major=\(major), minor=\(minor)): \(message)"
        }
    }
}
