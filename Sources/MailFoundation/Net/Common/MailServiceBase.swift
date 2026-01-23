//
// MailServiceBase.swift
//
// Base mail service abstractions and configuration (ported from MailKit).
//

import Foundation
#if canImport(Security)
@preconcurrency import Security
#endif

public enum TlsProtocolVersion: String, Sendable, CaseIterable {
    case tls10 = "TLS1.0"
    case tls11 = "TLS1.1"
    case tls12 = "TLS1.2"
    case tls13 = "TLS1.3"
}

public struct TlsConfiguration: Sendable, Equatable {
    public static let `default` = TlsConfiguration()

    public var allowedProtocols: Set<TlsProtocolVersion>
    public var cipherSuites: [String]?
    public var clientCertificates: [Data]
    public var validateServerCertificate: Bool
    public var checkCertificateRevocation: Bool

    public init(
        allowedProtocols: Set<TlsProtocolVersion> = [],
        cipherSuites: [String]? = nil,
        clientCertificates: [Data] = [],
        validateServerCertificate: Bool = true,
        checkCertificateRevocation: Bool = true
    ) {
        self.allowedProtocols = allowedProtocols
        self.cipherSuites = cipherSuites
        self.clientCertificates = clientCertificates
        self.validateServerCertificate = validateServerCertificate
        self.checkCertificateRevocation = checkCertificateRevocation
    }
}

public struct CertificateValidationContext: @unchecked Sendable {
    public let host: String
    public let port: Int
#if canImport(Security)
    public let trust: SecTrust?
#else
    public let trust: Any?
#endif

#if canImport(Security)
    public init(host: String, port: Int, trust: SecTrust?) {
        self.host = host
        self.port = port
        self.trust = trust
    }
#else
    public init(host: String, port: Int, trust: Any?) {
        self.host = host
        self.port = port
        self.trust = trust
    }
#endif
}

public typealias CertificateValidationHandler = @Sendable (CertificateValidationContext) -> Bool

public struct SocketEndpoint: Sendable, Equatable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public protocol ProxyClient: AnyObject {
    func connect(to host: String, port: Int) throws
}

open class MailServiceBase<Response>: MailService {
    public typealias ConnectResponse = Response

    public let syncRoot = NSObject()
    public var protocolLogger: ProtocolLoggerType
    public var tlsConfiguration: TlsConfiguration
    public var serverCertificateValidation: CertificateValidationHandler?
    public var localEndpoint: SocketEndpoint?
    public weak var proxyClient: (any ProxyClient)?

    public private(set) var authenticationMechanisms: Set<String> = []
    public private(set) var state: MailServiceState = .disconnected

    public var isConnected: Bool { state != .disconnected }
    public var isAuthenticated: Bool { state == .authenticated }

    public init(
        protocolLogger: ProtocolLoggerType = NullProtocolLogger(),
        tlsConfiguration: TlsConfiguration = .default
    ) {
        self.protocolLogger = protocolLogger
        self.tlsConfiguration = tlsConfiguration
    }

    open var protocolName: String {
        fatalError("Subclasses must override protocolName.")
    }

    @discardableResult
    open func connect() throws -> Response {
        fatalError("Subclasses must override connect().")
    }

    open func disconnect() {
        updateState(.disconnected)
    }

    public func updateAuthenticationMechanisms(_ mechanisms: [String]) {
        authenticationMechanisms = Set(mechanisms.map { $0.uppercased() })
    }

    public func addAuthenticationMechanism(_ mechanism: String) {
        authenticationMechanisms.insert(mechanism.uppercased())
    }

    public func removeAuthenticationMechanism(_ mechanism: String) {
        authenticationMechanisms.remove(mechanism.uppercased())
    }

    public func supportsAuthenticationMechanism(_ mechanism: String) -> Bool {
        authenticationMechanisms.contains(mechanism.uppercased())
    }

    public func updateState(_ newState: MailServiceState) {
        state = newState
    }
}

open class MailTransportBase<Response>: MailServiceBase<Response> {
    public struct MessageSentEvent: Sendable {
        public let response: String

        public init(response: String) {
            self.response = response
        }
    }

    public typealias MessageSentHandler = @Sendable (MessageSentEvent) -> Void

    private var messageSentHandlers: [MessageSentHandler] = []

    public func addMessageSentHandler(_ handler: @escaping MessageSentHandler) {
        messageSentHandlers.append(handler)
    }

    public func removeAllMessageSentHandlers() {
        messageSentHandlers.removeAll()
    }

    public func notifyMessageSent(response: String) {
        let event = MessageSentEvent(response: response)
        for handler in messageSentHandlers {
            handler(event)
        }
    }
}
