//
// MailServiceAbstractions.swift
//
// Base mail service/transport protocols (ported from MailKit abstractions).
//

public enum MailServiceState: Sendable, Equatable {
    case disconnected
    case connected
    case authenticated
}

public protocol MailService: AnyObject {
    associatedtype ConnectResponse

    var state: MailServiceState { get }
    var isConnected: Bool { get }
    var isAuthenticated: Bool { get }

    @discardableResult
    func connect() throws -> ConnectResponse
    func disconnect()
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMailService: AnyObject {
    associatedtype ConnectResponse

    var state: MailServiceState { get async }
    var isConnected: Bool { get async }
    var isAuthenticated: Bool { get async }

    @discardableResult
    func connect() async throws -> ConnectResponse
    func disconnect() async
}

public protocol MessageTransport: AnyObject {
    func sendMessage(from: String, to recipients: [String], data: [UInt8]) throws
}

public typealias MessageSentHandler = @Sendable (MessageSentEvent) -> Void

public protocol MailTransport: MailService, MessageTransport {
    func addMessageSentHandler(_ handler: @escaping MessageSentHandler)
    func removeAllMessageSentHandlers()
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMessageTransport: AnyObject {
    func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws
}

@available(macOS 10.15, iOS 13.0, *)
public typealias AsyncMessageSentHandler = @Sendable (MessageSentEvent) async -> Void

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMailTransport: AsyncMailService, AsyncMessageTransport {
    func addMessageSentHandler(_ handler: @escaping AsyncMessageSentHandler) async
    func removeAllMessageSentHandlers() async
}
