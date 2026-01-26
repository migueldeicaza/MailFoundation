import Testing
import MimeFoundation
@testable import MailFoundation

@Test("Delivery status notification parses groups and fields")
func deliveryStatusNotificationParsesGroups() throws {
    let messageGroup = HeaderList()
    messageGroup.add(Header(field: "Reporting-MTA", value: "dns; mail.example.com"))
    messageGroup.add(Header(field: "Received-From-MTA", value: "dns; gateway.example.net"))
    messageGroup.add(Header(field: "Arrival-Date", value: "Tue, 15 Jan 2024 12:00:00 -0500"))
    messageGroup.add(Header(field: "Original-Envelope-Id", value: "abc-123"))

    let recipientGroup = HeaderList()
    recipientGroup.add(Header(field: "Final-Recipient", value: "rfc822; user@example.com"))
    recipientGroup.add(Header(field: "Action", value: "failed"))
    recipientGroup.add(Header(field: "Status", value: "5.1.1"))
    recipientGroup.add(Header(field: "Diagnostic-Code", value: "smtp; 550 5.1.1 User unknown"))
    recipientGroup.add(Header(field: "Remote-MTA", value: "dns; mx.example.com"))
    recipientGroup.add(Header(field: "Last-Attempt-Date", value: "Tue, 15 Jan 2024 12:05:00 -0500"))
    recipientGroup.add(Header(field: "Final-Log-ID", value: "log-42"))
    recipientGroup.add(Header(field: "Will-Retry-Until", value: "Tue, 16 Jan 2024 12:00:00 -0500"))

    let status = MessageDeliveryStatus()
    status.statusGroups.add(messageGroup)
    status.statusGroups.add(recipientGroup)

    let notification = DeliveryStatusNotification(status: status)
    #expect(notification.messageFields?.reportingMta?.address == "mail.example.com")
    #expect(notification.messageFields?.receivedFromMta?.address == "gateway.example.net")
    #expect(notification.messageFields?.originalEnvelopeId == "abc-123")
    #expect(notification.messageFields?.arrivalDate != nil)
    #expect(notification.recipients.count == 1)

    let recipient = notification.recipients[0]
    #expect(recipient.finalRecipient?.address == "user@example.com")
    #expect(recipient.action == .failed)
    #expect(recipient.status?.rawValue == "5.1.1")
    #expect(recipient.diagnosticCode?.type == "smtp")
    #expect(recipient.diagnosticCode?.message.contains("User unknown") == true)
    #expect(recipient.remoteMta?.address == "mx.example.com")
    #expect(recipient.lastAttemptDate != nil)
    #expect(recipient.finalLogId == "log-42")
    #expect(recipient.willRetryUntil != nil)
}

@Test("Delivery status notification resolves from multipart report")
func deliveryStatusNotificationFromMultipartReport() throws {
    let status = MessageDeliveryStatus()
    let group = HeaderList()
    group.add(Header(field: "Reporting-MTA", value: "dns; mail.example.com"))
    status.statusGroups.add(group)

    let report = try MultipartReport(reportType: "delivery-status")
    try report.add(status)

    let message = MimeMessage()
    message.body = report

    let notification = DeliveryStatusNotification(message: message)
    #expect(notification?.messageFields?.reportingMta?.address == "mail.example.com")
}
