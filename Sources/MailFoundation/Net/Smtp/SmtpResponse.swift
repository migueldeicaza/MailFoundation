//
// SmtpResponse.swift
//
// Basic SMTP response model and parser.
//

public struct SmtpResponse: Sendable {
    public let code: Int
    public let lines: [String]

    public var isSuccess: Bool {
        code >= 200 && code < 400
    }

    public var isIntermediate: Bool {
        code >= 100 && code < 200
    }

    public var isError: Bool {
        code >= 400
    }
}

public struct SmtpResponseParser: Sendable {
    private var pendingCode: Int?
    private var pendingLines: [String] = []

    public init() {}

    public mutating func parseLine(_ line: String) -> SmtpResponse? {
        guard line.count >= 4 else {
            resetPendingIfNeeded()
            return nil
        }

        let codeStart = line.startIndex
        let codeEnd = line.index(codeStart, offsetBy: 3)
        let codeText = String(line[codeStart..<codeEnd])
        guard let code = Int(codeText) else {
            resetPendingIfNeeded()
            return nil
        }

        let separatorIndex = codeEnd
        guard separatorIndex < line.endIndex else {
            resetPendingIfNeeded()
            return nil
        }
        let remainderStart = line.index(after: separatorIndex)
        let separator = line[separatorIndex]
        let remainder = remainderStart <= line.endIndex ? String(line[remainderStart...]) : ""

        if let pendingCode, pendingCode != code {
            // Drop invalid mixed-code multiline state and treat this as a new response.
            self.pendingCode = nil
            pendingLines.removeAll(keepingCapacity: true)
        }
        if pendingCode == nil {
            pendingCode = code
        }

        pendingLines.append(remainder)

        if separator == "-" {
            return nil
        }

        let response = SmtpResponse(code: pendingCode ?? code, lines: pendingLines)
        pendingCode = nil
        pendingLines.removeAll(keepingCapacity: true)
        return response
    }

    private mutating func resetPendingIfNeeded() {
        guard pendingCode != nil else { return }
        pendingCode = nil
        pendingLines.removeAll(keepingCapacity: true)
    }
}
