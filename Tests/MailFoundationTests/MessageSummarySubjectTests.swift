import Testing
@testable import MailFoundation

@Test("MessageSummary derives normalized subject and reply state")
func messageSummarySubjectDerivedFields() {
    let emptySummary = MessageSummary(sequence: 1)
    #expect(emptySummary.normalizedSubject == "")
    #expect(emptySummary.isReply == false)

    let envelope = ImapEnvelope(
        date: nil,
        subject: "Re: Re[2]: example",
        from: [],
        sender: [],
        replyTo: [],
        to: [],
        cc: [],
        bcc: [],
        inReplyTo: nil,
        messageId: nil
    )
    let summary = MessageSummary(sequence: 1, envelope: envelope)
    #expect(summary.normalizedSubject == "example")
    #expect(summary.isReply == true)
}
