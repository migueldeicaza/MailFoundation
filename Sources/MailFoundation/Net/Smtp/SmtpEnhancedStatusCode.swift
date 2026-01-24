//
// SmtpEnhancedStatusCode.swift
//
// RFC 3463 enhanced status codes.
//

public struct SmtpEnhancedStatusCode: Sendable, Equatable, CustomStringConvertible {
    public let klass: Int
    public let subject: Int
    public let detail: Int

    public init(klass: Int, subject: Int, detail: Int) {
        self.klass = klass
        self.subject = subject
        self.detail = detail
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let klass = Int(parts[0]),
              let subject = Int(parts[1]),
              let detail = Int(parts[2]) else {
            return nil
        }
        self.klass = klass
        self.subject = subject
        self.detail = detail
    }

    public static func parse(from line: String) -> SmtpEnhancedStatusCode? {
        guard let token = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" }).first else {
            return nil
        }
        return SmtpEnhancedStatusCode(String(token))
    }

    public var description: String {
        "\(klass).\(subject).\(detail)"
    }
}

public extension SmtpResponse {
    var enhancedStatusCodes: [SmtpEnhancedStatusCode] {
        lines.compactMap(SmtpEnhancedStatusCode.parse(from:))
    }

    var enhancedStatusCode: SmtpEnhancedStatusCode? {
        enhancedStatusCodes.first
    }
}
