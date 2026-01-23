//
// ImapSessionState.swift
//
// Unified IMAP session state for sync/async clients.
//

public enum ImapSessionState: Sendable, Equatable {
    case disconnected
    case connected
    case authenticating
    case authenticated
    case selected
}

public extension ImapSessionState {
    init(_ state: ImapClient.State) {
        switch state {
        case .disconnected:
            self = .disconnected
        case .connected:
            self = .connected
        case .authenticating:
            self = .authenticating
        case .authenticated:
            self = .authenticated
        case .selected:
            self = .selected
        }
    }
}

@available(macOS 10.15, iOS 13.0, *)
public extension ImapSessionState {
    init(_ state: AsyncImapClient.State) {
        switch state {
        case .disconnected:
            self = .disconnected
        case .connected:
            self = .connected
        case .authenticating:
            self = .authenticating
        case .authenticated:
            self = .authenticated
        case .selected:
            self = .selected
        }
    }
}
