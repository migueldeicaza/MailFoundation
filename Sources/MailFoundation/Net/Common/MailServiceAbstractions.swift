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

public protocol MailTransport: MailService, MessageTransport {}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMessageTransport: AnyObject {
    func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMailTransport: AsyncMailService, AsyncMessageTransport {}
