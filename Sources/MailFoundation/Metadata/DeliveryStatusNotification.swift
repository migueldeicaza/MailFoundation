//
// DeliveryStatusNotification.swift
//
// Delivery status notification helpers backed by MessageDeliveryStatus.
//

import Foundation
import MimeFoundation

public struct DeliveryStatusNotification: Sendable, Equatable {
    public let messageFields: DeliveryStatusFields?
    public let recipients: [DeliveryStatusRecipient]

    public init(messageFields: DeliveryStatusFields?, recipients: [DeliveryStatusRecipient]) {
        self.messageFields = messageFields
        self.recipients = recipients
    }

    public init(status: MessageDeliveryStatus) {
        let groups = status.statusGroups
        if groups.isEmpty {
            self.messageFields = nil
            self.recipients = []
            return
        }
        self.messageFields = DeliveryStatusFields(headers: groups[0])
        if groups.count > 1 {
            self.recipients = (1..<groups.count).map { DeliveryStatusRecipient(headers: groups[$0]) }
        } else {
            self.recipients = []
        }
    }

    public init?(message: MimeMessage) {
        guard let entity = message.body else { return nil }
        self.init(entity: entity)
    }

    public init?(entity: MimeEntity) {
        guard let status = DeliveryStatusNotification.findStatus(in: entity) else { return nil }
        self.init(status: status)
    }

    private static func findStatus(in entity: MimeEntity) -> MessageDeliveryStatus? {
        if let status = entity as? MessageDeliveryStatus {
            return status
        }
        if let report = entity as? MultipartReport {
            if report.reportType?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "delivery-status" {
                for index in report.indices {
                    let part = report[index]
                    if let status = part as? MessageDeliveryStatus {
                        return status
                    }
                }
            }
        }
        return nil
    }
}

public struct DeliveryStatusFields: Sendable, Equatable {
    public let reportingMta: DeliveryStatusAddress?
    public let receivedFromMta: DeliveryStatusAddress?
    public let originalEnvelopeId: String?
    public let arrivalDate: Date?
    public let mtaName: String?
    public let otherFields: [String: [String]]

    init(headers: HeaderList) {
        var remaining = DeliveryStatusFields.collectFields(headers)
        reportingMta = DeliveryStatusAddress.parse(remaining.popFirstValue(for: "reporting-mta"))
        receivedFromMta = DeliveryStatusAddress.parse(remaining.popFirstValue(for: "received-from-mta"))
        originalEnvelopeId = remaining.popFirstValue(for: "original-envelope-id")
        if let arrival = remaining.popFirstValue(for: "arrival-date") {
            arrivalDate = DateUtils.tryParse(arrival)
        } else {
            arrivalDate = nil
        }
        mtaName = remaining.popFirstValue(for: "mta-name")
        otherFields = remaining
    }

    fileprivate static func collectFields(_ headers: HeaderList) -> [String: [String]] {
        var fields: [String: [String]] = [:]
        for header in headers {
            let key = header.field.lowercased()
            fields[key, default: []].append(header.value)
        }
        return fields
    }
}

public struct DeliveryStatusRecipient: Sendable, Equatable {
    public let originalRecipient: DeliveryStatusAddress?
    public let finalRecipient: DeliveryStatusAddress?
    public let action: DeliveryStatusAction?
    public let status: DeliveryStatusCode?
    public let remoteMta: DeliveryStatusAddress?
    public let diagnosticCode: DeliveryStatusDiagnostic?
    public let lastAttemptDate: Date?
    public let finalLogId: String?
    public let willRetryUntil: Date?
    public let otherFields: [String: [String]]

    init(headers: HeaderList) {
        var remaining = DeliveryStatusFields.collectFields(headers)
        originalRecipient = DeliveryStatusAddress.parse(remaining.popFirstValue(for: "original-recipient"))
        finalRecipient = DeliveryStatusAddress.parse(remaining.popFirstValue(for: "final-recipient"))
        if let actionValue = remaining.popFirstValue(for: "action") {
            action = DeliveryStatusAction.parse(actionValue)
        } else {
            action = nil
        }
        if let statusValue = remaining.popFirstValue(for: "status") {
            status = DeliveryStatusCode(rawValue: statusValue)
        } else {
            status = nil
        }
        remoteMta = DeliveryStatusAddress.parse(remaining.popFirstValue(for: "remote-mta"))
        diagnosticCode = DeliveryStatusDiagnostic.parse(remaining.popFirstValue(for: "diagnostic-code"))
        if let lastAttempt = remaining.popFirstValue(for: "last-attempt-date") {
            lastAttemptDate = DateUtils.tryParse(lastAttempt)
        } else {
            lastAttemptDate = nil
        }
        finalLogId = remaining.popFirstValue(for: "final-log-id")
        if let retryUntil = remaining.popFirstValue(for: "will-retry-until") {
            willRetryUntil = DateUtils.tryParse(retryUntil)
        } else {
            willRetryUntil = nil
        }
        otherFields = remaining
    }
}

public enum DeliveryStatusAction: String, Sendable, Equatable {
    case failed
    case delayed
    case delivered
    case relayed
    case expanded

    static func parse(_ value: String) -> DeliveryStatusAction? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DeliveryStatusAction(rawValue: normalized)
    }
}

public struct DeliveryStatusAddress: Sendable, Equatable {
    public let type: String
    public let address: String

    public init(type: String, address: String) {
        self.type = type
        self.address = address
    }

    static func parse(_ value: String?) -> DeliveryStatusAddress? {
        guard let value else { return nil }
        let parts = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let type = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let address = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !address.isEmpty else { return nil }
        return DeliveryStatusAddress(type: type, address: address)
    }
}

public struct DeliveryStatusDiagnostic: Sendable, Equatable {
    public let type: String
    public let message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }

    static func parse(_ value: String?) -> DeliveryStatusDiagnostic? {
        guard let value else { return nil }
        let parts = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let type = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let message = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !message.isEmpty else { return nil }
        return DeliveryStatusDiagnostic(type: type, message: message)
    }
}

public struct DeliveryStatusCode: Sendable, Equatable {
    public let classCode: Int
    public let subject: Int
    public let detail: Int
    public let rawValue: String

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? trimmed
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let classCode = Int(parts[0]),
              let subject = Int(parts[1]),
              let detail = Int(parts[2]) else {
            return nil
        }
        self.classCode = classCode
        self.subject = subject
        self.detail = detail
        self.rawValue = "\(classCode).\(subject).\(detail)"
    }
}

private extension Dictionary where Key == String, Value == [String] {
    mutating func popFirstValue(for key: String) -> String? {
        guard var values = self[key], !values.isEmpty else { return nil }
        let first = values.removeFirst()
        if values.isEmpty {
            self[key] = nil
        } else {
            self[key] = values
        }
        return first
    }
}
