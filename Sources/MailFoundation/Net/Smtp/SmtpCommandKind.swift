//
// SmtpCommandKind.swift
//
// SMTP command definitions.
//

public enum SmtpCommandKind: Sendable {
    case helo(String)
    case ehlo(String)
    case mailFrom(String)
    case mailFromParameters(String, SmtpMailFromParameters)
    case rcptTo(String)
    case rcptToParameters(String, SmtpRcptToParameters)
    case data
    case bdat(Int, last: Bool)
    case rset
    case noop
    case quit
    case starttls
    case vrfy(String)
    case expn(String)
    case help(String?)
    case etrn(String)
    case auth(String, initialResponse: String?)

    public func command() -> SmtpCommand {
        switch self {
        case let .helo(domain):
            return SmtpCommand(keyword: "HELO", arguments: domain)
        case let .ehlo(domain):
            return SmtpCommand(keyword: "EHLO", arguments: domain)
        case let .mailFrom(address):
            return SmtpCommand(keyword: "MAIL", arguments: "FROM:<\(address)>")
        case let .mailFromParameters(address, parameters):
            let args = parameters.arguments()
            if args.isEmpty {
                return SmtpCommand(keyword: "MAIL", arguments: "FROM:<\(address)>")
            }
            return SmtpCommand(keyword: "MAIL", arguments: "FROM:<\(address)> \(args.joined(separator: " "))")
        case let .rcptTo(address):
            return SmtpCommand(keyword: "RCPT", arguments: "TO:<\(address)>")
        case let .rcptToParameters(address, parameters):
            let args = parameters.arguments()
            if args.isEmpty {
                return SmtpCommand(keyword: "RCPT", arguments: "TO:<\(address)>")
            }
            return SmtpCommand(keyword: "RCPT", arguments: "TO:<\(address)> \(args.joined(separator: " "))")
        case .data:
            return SmtpCommand(keyword: "DATA")
        case let .bdat(size, last):
            if last {
                return SmtpCommand(keyword: "BDAT", arguments: "\(size) LAST")
            }
            return SmtpCommand(keyword: "BDAT", arguments: "\(size)")
        case .rset:
            return SmtpCommand(keyword: "RSET")
        case .noop:
            return SmtpCommand(keyword: "NOOP")
        case .quit:
            return SmtpCommand(keyword: "QUIT")
        case .starttls:
            return SmtpCommand(keyword: "STARTTLS")
        case let .vrfy(argument):
            return SmtpCommand(keyword: "VRFY", arguments: argument)
        case let .expn(argument):
            return SmtpCommand(keyword: "EXPN", arguments: argument)
        case let .help(argument):
            if let argument {
                return SmtpCommand(keyword: "HELP", arguments: argument)
            }
            return SmtpCommand(keyword: "HELP")
        case let .etrn(argument):
            return SmtpCommand(keyword: "ETRN", arguments: argument)
        case let .auth(mechanism, initialResponse):
            if let response = initialResponse {
                return SmtpCommand(keyword: "AUTH", arguments: "\(mechanism) \(response)")
            }
            return SmtpCommand(keyword: "AUTH", arguments: mechanism)
        }
    }
}
