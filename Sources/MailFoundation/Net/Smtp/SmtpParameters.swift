//
// SmtpParameters.swift
//
// SMTP extension parameter models (SMTPUTF8/DSN/CHUNKING helpers).
//

public enum SmtpBodyKind: String, Sendable, Equatable {
    case sevenBit = "7BIT"
    case eightBitMime = "8BITMIME"
    case binaryMime = "BINARYMIME"
}

public enum SmtpReturnOption: String, Sendable, Equatable {
    case full = "FULL"
    case headers = "HDRS"
}

public enum SmtpNotifyOption: String, Sendable, Equatable {
    case never = "NEVER"
    case success = "SUCCESS"
    case failure = "FAILURE"
    case delay = "DELAY"
}

public struct SmtpMailFromParameters: Sendable, Equatable {
    public var smtpUtf8: Bool
    public var body: SmtpBodyKind?
    public var size: Int?
    public var ret: SmtpReturnOption?
    public var envid: String?
    public var requireTls: Bool
    public var additional: [String]

    public init(
        smtpUtf8: Bool = false,
        body: SmtpBodyKind? = nil,
        size: Int? = nil,
        ret: SmtpReturnOption? = nil,
        envid: String? = nil,
        requireTls: Bool = false,
        additional: [String] = []
    ) {
        self.smtpUtf8 = smtpUtf8
        self.body = body
        self.size = size
        self.ret = ret
        self.envid = envid
        self.requireTls = requireTls
        self.additional = additional
    }

    public func arguments() -> [String] {
        var args: [String] = []
        if smtpUtf8 {
            args.append("SMTPUTF8")
        }
        if let body {
            args.append("BODY=\(body.rawValue)")
        }
        if let size {
            args.append("SIZE=\(size)")
        }
        if let ret {
            args.append("RET=\(ret.rawValue)")
        }
        if let envid {
            args.append("ENVID=\(envid)")
        }
        if requireTls {
            args.append("REQUIRETLS")
        }
        if !additional.isEmpty {
            args.append(contentsOf: additional)
        }
        return args
    }
}

public struct SmtpRcptToParameters: Sendable, Equatable {
    public var notify: [SmtpNotifyOption]
    public var orcpt: String?
    public var additional: [String]

    public init(
        notify: [SmtpNotifyOption] = [],
        orcpt: String? = nil,
        additional: [String] = []
    ) {
        self.notify = notify
        self.orcpt = orcpt
        self.additional = additional
    }

    public func arguments() -> [String] {
        var args: [String] = []
        if !notify.isEmpty {
            let value = notify.map { $0.rawValue }.joined(separator: ",")
            args.append("NOTIFY=\(value)")
        }
        if let orcpt {
            args.append("ORCPT=\(orcpt)")
        }
        if !additional.isEmpty {
            args.append(contentsOf: additional)
        }
        return args
    }
}
