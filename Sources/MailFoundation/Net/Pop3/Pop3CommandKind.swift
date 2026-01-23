//
// Pop3CommandKind.swift
//
// POP3 command definitions.
//

public enum Pop3CommandKind: Sendable {
    case user(String)
    case pass(String)
    case stat
    case list(Int?)
    case retr(Int)
    case dele(Int)
    case noop
    case rset
    case quit
    case uidl(Int?)
    case top(Int, lines: Int)
    case capa
    case stls
    case apop(String, String)
    case auth(String, initialResponse: String?)
    case last

    public func command() -> Pop3Command {
        switch self {
        case let .user(name):
            return Pop3Command(keyword: "USER", arguments: name)
        case let .pass(password):
            return Pop3Command(keyword: "PASS", arguments: password)
        case .stat:
            return Pop3Command(keyword: "STAT")
        case let .list(index):
            if let index {
                return Pop3Command(keyword: "LIST", arguments: "\(index)")
            }
            return Pop3Command(keyword: "LIST")
        case let .retr(index):
            return Pop3Command(keyword: "RETR", arguments: "\(index)")
        case let .dele(index):
            return Pop3Command(keyword: "DELE", arguments: "\(index)")
        case .noop:
            return Pop3Command(keyword: "NOOP")
        case .rset:
            return Pop3Command(keyword: "RSET")
        case .quit:
            return Pop3Command(keyword: "QUIT")
        case let .uidl(index):
            if let index {
                return Pop3Command(keyword: "UIDL", arguments: "\(index)")
            }
            return Pop3Command(keyword: "UIDL")
        case let .top(index, lines):
            return Pop3Command(keyword: "TOP", arguments: "\(index) \(lines)")
        case .capa:
            return Pop3Command(keyword: "CAPA")
        case .stls:
            return Pop3Command(keyword: "STLS")
        case let .apop(user, digest):
            return Pop3Command(keyword: "APOP", arguments: "\(user) \(digest)")
        case let .auth(mechanism, initialResponse):
            if let response = initialResponse {
                return Pop3Command(keyword: "AUTH", arguments: "\(mechanism) \(response)")
            }
            return Pop3Command(keyword: "AUTH", arguments: mechanism)
        case .last:
            return Pop3Command(keyword: "LAST")
        }
    }
}
