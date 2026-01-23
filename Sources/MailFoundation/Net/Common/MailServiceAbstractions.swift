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
    var state: MailServiceState { get }
    var isConnected: Bool { get }
    var isAuthenticated: Bool { get }

    func connect() throws
    func disconnect()
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMailService: AnyObject {
    var state: MailServiceState { get }
    var isConnected: Bool { get }
    var isAuthenticated: Bool { get }

    func connect() async throws
    func disconnect() async
}

public protocol MessageTransport: AnyObject {
    func sendMessage(from: String, to recipients: [String], data: [UInt8]) throws
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMessageTransport: AnyObject {
    func sendMessage(from: String, to recipients: [String], data: [UInt8]) async throws
}
