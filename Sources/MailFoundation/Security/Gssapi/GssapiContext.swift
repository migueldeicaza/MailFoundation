//
// GssapiContext.swift
//
// GSSAPI security context wrapper for Kerberos authentication.
//

import Foundation

#if canImport(GSS)
@preconcurrency import GSS

// Swift doesn't import C macros, so we access the globals through computed properties
// These OIDs are effectively read-only constants in the GSS API
extension GssapiContext {
    fileprivate static var ntUserNameOID: gss_OID {
        withUnsafeMutablePointer(to: &__gss_c_nt_user_name_oid_desc) { $0 }
    }

    fileprivate static var ntHostbasedServiceOID: gss_OID {
        withUnsafeMutablePointer(to: &__gss_c_nt_hostbased_service_oid_desc) { $0 }
    }
}
#endif

/// GSSAPI security layer options per RFC 2222 Section 7.2.
public struct GssapiSecurityLayer: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// No security layer - authentication only.
    public static let none = GssapiSecurityLayer(rawValue: 0x01)

    /// Integrity protection (message signing).
    public static let integrity = GssapiSecurityLayer(rawValue: 0x02)

    /// Confidentiality protection (encryption).
    public static let confidentiality = GssapiSecurityLayer(rawValue: 0x04)
}

/// A wrapper around GSSAPI security context for Kerberos authentication.
///
/// This class manages the GSSAPI authentication flow, including:
/// - Initial token generation
/// - Challenge-response processing
/// - Security layer negotiation (per RFC 2222)
///
/// ## Platform Support
///
/// GSSAPI is available on macOS and iOS through the GSS framework.
/// Use ``isAvailable`` to check platform support.
///
/// ## Usage
///
/// ```swift
/// let context = GssapiContext(
///     servicePrincipalName: "imap/mail.example.com",
///     username: "user@EXAMPLE.COM",
///     password: "secret"
/// )
///
/// // Generate initial token
/// let initialToken = try context.initSecContext(inputToken: nil)
///
/// // Process server challenges
/// while !context.isComplete {
///     let response = try context.initSecContext(inputToken: serverChallenge)
/// }
/// ```
public final class GssapiContext: @unchecked Sendable {
    /// Whether GSSAPI is available on this platform.
    public static var isAvailable: Bool {
        #if canImport(GSS)
        return true
        #else
        return false
        #endif
    }

    /// The service principal name (e.g., "imap/mail.example.com").
    public let servicePrincipalName: String

    /// The username for authentication.
    public let username: String?

    /// Whether the authentication context is complete.
    public private(set) var isComplete: Bool = false

    /// Whether a security layer was negotiated.
    public private(set) var negotiatedSecurityLayer: Bool = false

    /// The desired security layer (default: none).
    public var desiredSecurityLayer: GssapiSecurityLayer = .none

    /// Maximum message size for wrapped messages (default: 0 = no limit).
    public var maxMessageSize: UInt32 = 0

    #if canImport(GSS)
    private var contextHandle: gss_ctx_id_t?
    private var credentialHandle: gss_cred_id_t?
    private let password: String?
    #endif

    /// Initializes a new GSSAPI context.
    ///
    /// - Parameters:
    ///   - servicePrincipalName: The SPN of the service (e.g., "imap/mail.example.com").
    ///   - username: Optional username for credential acquisition.
    ///   - password: Optional password for credential acquisition.
    public init(
        servicePrincipalName: String,
        username: String? = nil,
        password: String? = nil
    ) {
        self.servicePrincipalName = servicePrincipalName
        self.username = username
        #if canImport(GSS)
        self.password = password
        #endif
    }

    deinit {
        #if canImport(GSS)
        cleanup()
        #endif
    }

    #if canImport(GSS)
    private func cleanup() {
        var minorStatus: OM_uint32 = 0
        if contextHandle != nil {
            gss_delete_sec_context(&minorStatus, &contextHandle, nil)
            contextHandle = nil
        }
        if credentialHandle != nil {
            gss_release_cred(&minorStatus, &credentialHandle)
            credentialHandle = nil
        }
    }

    /// Acquires credentials for authentication.
    private func acquireCredentials() throws {
        guard credentialHandle == nil else { return }

        var minorStatus: OM_uint32 = 0
        var majorStatus: OM_uint32 = 0

        // Use default credentials if no username/password provided
        if username == nil && password == nil {
            // Use default credential cache (nil credential handle)
            return
        }

        // Import the username as a GSS name
        guard let user = username else {
            return
        }

        var inputName = gss_buffer_desc()
        var userBytes = Array(user.utf8)

        var gssName: gss_name_t?
        majorStatus = userBytes.withUnsafeMutableBufferPointer { ptr in
            inputName.length = ptr.count
            inputName.value = UnsafeMutableRawPointer(ptr.baseAddress)

            return gss_import_name(
                &minorStatus,
                &inputName,
                Self.ntUserNameOID,
                &gssName
            )
        }

        if majorStatus != UInt32(GSS_S_COMPLETE) {
            throw GssapiError.credentialAcquisitionFailed(
                gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
            )
        }

        defer {
            if gssName != nil {
                gss_release_name(&minorStatus, &gssName)
            }
        }

        // If password is provided, acquire credentials with password
        if let pwd = password {
            var pwdBuffer = gss_buffer_desc()
            var pwdBytes = Array(pwd.utf8)

            majorStatus = pwdBytes.withUnsafeMutableBufferPointer { ptr in
                pwdBuffer.length = ptr.count
                pwdBuffer.value = UnsafeMutableRawPointer(ptr.baseAddress)

                return gss_acquire_cred_with_password(
                    &minorStatus,
                    gssName!,
                    &pwdBuffer,
                    0,  // time_req
                    nil,  // GSS_C_NO_OID_SET
                    GSS_C_INITIATE,
                    &credentialHandle,
                    nil,
                    nil
                )
            }

            if majorStatus != UInt32(GSS_S_COMPLETE) {
                throw GssapiError.credentialAcquisitionFailed(
                    gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
                )
            }
        } else {
            // Acquire credentials from default cache for this user
            majorStatus = gss_acquire_cred(
                &minorStatus,
                gssName!,
                0,  // time_req
                nil,  // GSS_C_NO_OID_SET
                GSS_C_INITIATE,
                &credentialHandle,
                nil,
                nil
            )

            if majorStatus != UInt32(GSS_S_COMPLETE) {
                throw GssapiError.credentialAcquisitionFailed(
                    gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
                )
            }
        }
    }

    /// Displays a GSS error status as a human-readable string.
    private func gssDisplayStatus(majorStatus: OM_uint32, minorStatus: OM_uint32) -> String {
        var msgBuffer = gss_buffer_desc()
        var msgContext: OM_uint32 = 0
        var minor: OM_uint32 = 0
        var messages: [String] = []

        // Display major status
        repeat {
            gss_display_status(
                &minor,
                majorStatus,
                GSS_C_GSS_CODE,
                nil,  // GSS_C_NO_OID
                &msgContext,
                &msgBuffer
            )
            if let ptr = msgBuffer.value {
                let data = Data(bytes: ptr, count: msgBuffer.length)
                if let msg = String(data: data, encoding: .utf8) {
                    messages.append(msg)
                }
            }
            gss_release_buffer(&minor, &msgBuffer)
        } while msgContext != 0

        // Display minor status
        msgContext = 0
        repeat {
            gss_display_status(
                &minor,
                minorStatus,
                GSS_C_MECH_CODE,
                nil,  // GSS_C_NO_OID
                &msgContext,
                &msgBuffer
            )
            if let ptr = msgBuffer.value {
                let data = Data(bytes: ptr, count: msgBuffer.length)
                if let msg = String(data: data, encoding: .utf8), !msg.isEmpty {
                    messages.append(msg)
                }
            }
            gss_release_buffer(&minor, &msgBuffer)
        } while msgContext != 0

        return messages.joined(separator: "; ")
    }
    #endif

    /// Initializes the security context with an optional input token.
    ///
    /// Call this method repeatedly until ``isComplete`` is true:
    /// 1. First call with `inputToken: nil` to get initial token
    /// 2. Subsequent calls with server challenge tokens
    ///
    /// - Parameter inputToken: The server's challenge token, or nil for initial call.
    /// - Returns: The output token to send to the server.
    /// - Throws: ``GssapiError`` if context initialization fails.
    public func initSecContext(inputToken: Data?) throws -> Data {
        #if canImport(GSS)
        try acquireCredentials()

        var minorStatus: OM_uint32 = 0

        // Import target name (SPN)
        var targetNameBuffer = gss_buffer_desc()
        var spnBytes = Array(servicePrincipalName.utf8)
        var targetName: gss_name_t?

        var majorStatus = spnBytes.withUnsafeMutableBufferPointer { ptr in
            targetNameBuffer.length = ptr.count
            targetNameBuffer.value = UnsafeMutableRawPointer(ptr.baseAddress)

            return gss_import_name(
                &minorStatus,
                &targetNameBuffer,
                Self.ntHostbasedServiceOID,
                &targetName
            )
        }

        if majorStatus != UInt32(GSS_S_COMPLETE) {
            throw GssapiError.contextInitFailed(
                gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
            )
        }

        defer {
            if targetName != nil {
                gss_release_name(&minorStatus, &targetName)
            }
        }

        // Prepare input token
        var inputTokenBuffer = gss_buffer_desc()
        var inputTokenBytes: [UInt8]?
        if let token = inputToken {
            inputTokenBytes = Array(token)
        }

        // Prepare output token
        var outputTokenBuffer = gss_buffer_desc()
        var retFlags: OM_uint32 = 0

        let reqFlags = UInt32(GSS_C_MUTUAL_FLAG | GSS_C_REPLAY_FLAG | GSS_C_SEQUENCE_FLAG | GSS_C_INTEG_FLAG)

        if var bytes = inputTokenBytes {
            majorStatus = bytes.withUnsafeMutableBufferPointer { ptr in
                inputTokenBuffer.length = ptr.count
                inputTokenBuffer.value = UnsafeMutableRawPointer(ptr.baseAddress)

                return gss_init_sec_context(
                    &minorStatus,
                    credentialHandle,  // nil means default credentials
                    &contextHandle,
                    targetName!,
                    nil,  // GSS_C_NO_OID - Use default mechanism (Kerberos)
                    reqFlags,
                    0,  // time_req
                    nil,  // GSS_C_NO_CHANNEL_BINDINGS
                    &inputTokenBuffer,
                    nil,
                    &outputTokenBuffer,
                    &retFlags,
                    nil
                )
            }
        } else {
            inputTokenBuffer.length = 0
            inputTokenBuffer.value = nil

            majorStatus = gss_init_sec_context(
                &minorStatus,
                credentialHandle,
                &contextHandle,
                targetName!,
                nil,
                reqFlags,
                0,
                nil,
                &inputTokenBuffer,
                nil,
                &outputTokenBuffer,
                &retFlags,
                nil
            )
        }

        defer {
            gss_release_buffer(&minorStatus, &outputTokenBuffer)
        }

        // Check result - GSS_S_COMPLETE = 0, continuation has specific bits set
        if majorStatus == UInt32(GSS_S_COMPLETE) {
            isComplete = true
        } else if (majorStatus & 0xFFFF0000) == 0 && majorStatus != 0 {
            // Supplementary status codes (like continue needed) are in lower bits
            // GSS_S_CONTINUE_NEEDED = 1 << 32 in the supplementary offset
            isComplete = false
        } else {
            throw GssapiError.contextInitFailed(
                gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
            )
        }

        // Copy output token
        if outputTokenBuffer.length > 0, let ptr = outputTokenBuffer.value {
            return Data(bytes: ptr, count: outputTokenBuffer.length)
        }
        return Data()
        #else
        throw GssapiError.notAvailable
        #endif
    }

    /// Wraps a message for secure transmission.
    ///
    /// - Parameters:
    ///   - message: The message to wrap.
    ///   - confidential: Whether to encrypt (true) or just sign (false).
    /// - Returns: The wrapped message.
    /// - Throws: ``GssapiError`` if wrapping fails.
    public func wrap(message: Data, confidential: Bool = false) throws -> Data {
        #if canImport(GSS)
        guard isComplete, contextHandle != nil else {
            throw GssapiError.authenticationIncomplete
        }

        var minorStatus: OM_uint32 = 0
        var inputBuffer = gss_buffer_desc()
        var outputBuffer = gss_buffer_desc()
        var confState: Int32 = 0

        var messageBytes = Array(message)
        let majorStatus = messageBytes.withUnsafeMutableBufferPointer { ptr in
            inputBuffer.length = ptr.count
            inputBuffer.value = UnsafeMutableRawPointer(ptr.baseAddress)

            return gss_wrap(
                &minorStatus,
                contextHandle!,
                confidential ? 1 : 0,
                UInt32(GSS_C_QOP_DEFAULT),
                &inputBuffer,
                &confState,
                &outputBuffer
            )
        }

        defer {
            gss_release_buffer(&minorStatus, &outputBuffer)
        }

        if majorStatus != UInt32(GSS_S_COMPLETE) {
            throw GssapiError.wrapFailed(
                gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
            )
        }

        if outputBuffer.length > 0, let ptr = outputBuffer.value {
            return Data(bytes: ptr, count: outputBuffer.length)
        }
        return Data()
        #else
        throw GssapiError.notAvailable
        #endif
    }

    /// Unwraps a secure message.
    ///
    /// - Parameter message: The wrapped message.
    /// - Returns: The unwrapped message.
    /// - Throws: ``GssapiError`` if unwrapping fails.
    public func unwrap(message: Data) throws -> Data {
        #if canImport(GSS)
        guard isComplete, contextHandle != nil else {
            throw GssapiError.authenticationIncomplete
        }

        var minorStatus: OM_uint32 = 0
        var inputBuffer = gss_buffer_desc()
        var outputBuffer = gss_buffer_desc()
        var confState: Int32 = 0
        var qopState: OM_uint32 = 0

        var messageBytes = Array(message)
        let majorStatus = messageBytes.withUnsafeMutableBufferPointer { ptr in
            inputBuffer.length = ptr.count
            inputBuffer.value = UnsafeMutableRawPointer(ptr.baseAddress)

            return gss_unwrap(
                &minorStatus,
                contextHandle!,
                &inputBuffer,
                &outputBuffer,
                &confState,
                &qopState
            )
        }

        defer {
            gss_release_buffer(&minorStatus, &outputBuffer)
        }

        if majorStatus != UInt32(GSS_S_COMPLETE) {
            throw GssapiError.wrapFailed(
                gssDisplayStatus(majorStatus: majorStatus, minorStatus: minorStatus)
            )
        }

        if outputBuffer.length > 0, let ptr = outputBuffer.value {
            return Data(bytes: ptr, count: outputBuffer.length)
        }
        return Data()
        #else
        throw GssapiError.notAvailable
        #endif
    }

    /// Processes the security layer negotiation challenge from the server.
    ///
    /// Per RFC 2222 Section 7.2, after authentication completes, the server
    /// sends a wrapped message containing:
    /// - Byte 0: Supported security layers (bit mask)
    /// - Bytes 1-3: Maximum message size (network byte order)
    ///
    /// - Parameter challenge: The server's security layer challenge.
    /// - Returns: The client's security layer response.
    /// - Throws: ``GssapiError`` if negotiation fails.
    public func negotiateSecurityLayer(challenge: Data) throws -> Data {
        #if canImport(GSS)
        // Unwrap the server's challenge
        let unwrapped = try unwrap(message: challenge)

        guard unwrapped.count >= 4 else {
            throw GssapiError.securityLayerNegotiationFailed
        }

        let serverLayers = unwrapped[0]
        // let maxSize = (UInt32(unwrapped[1]) << 16) | (UInt32(unwrapped[2]) << 8) | UInt32(unwrapped[3])

        // Check that server supports "no security layer" (bit 0)
        if (serverLayers & 0x01) == 0 {
            throw GssapiError.securityLayerNotSupported
        }

        // Select "no security layer" - same as MailKit
        var response = Data(count: 4)
        response[0] = 0x01  // No security layer
        response[1] = 0x00  // Max size = 0 (no limit)
        response[2] = 0x00
        response[3] = 0x00

        // Wrap the response
        let wrappedResponse = try wrap(message: response, confidential: false)
        negotiatedSecurityLayer = true

        return wrappedResponse
        #else
        throw GssapiError.notAvailable
        #endif
    }

    /// Resets the context for reuse.
    public func reset() {
        #if canImport(GSS)
        cleanup()
        #endif
        isComplete = false
        negotiatedSecurityLayer = false
    }
}
