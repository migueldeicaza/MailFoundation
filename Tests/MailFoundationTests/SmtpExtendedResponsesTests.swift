import Testing
@testable import MailFoundation

@Test
func smtpExtendedResponsesExposeEnhancedStatusCodes() {
    let response = SmtpResponse(code: 250, lines: [
        "2.1.5 <alice@example.com>",
        "2.1.0 <bob@example.com>"
    ])

    let vrfy = SmtpVrfyResult(response: response)
    #expect(vrfy.enhancedStatusCodes.count == 2)
    #expect(vrfy.enhancedStatusCode == SmtpEnhancedStatusCode("2.1.5"))

    let expn = SmtpExpnResult(response: response)
    #expect(expn.enhancedStatusCodes.count == 2)
    #expect(expn.enhancedStatusCode == SmtpEnhancedStatusCode("2.1.5"))

    let help = SmtpHelpResult(response: response)
    #expect(help.enhancedStatusCodes.count == 2)
    #expect(help.enhancedStatusCode == SmtpEnhancedStatusCode("2.1.5"))
}
