import Testing
@testable import MailFoundation

@Test
func parseEnhancedStatusCodeToken() {
    let code = SmtpEnhancedStatusCode("2.1.5")
    #expect(code != nil)
    #expect(code?.klass == 2)
    #expect(code?.subject == 1)
    #expect(code?.detail == 5)
    #expect(code?.description == "2.1.5")
}

@Test
func parseEnhancedStatusCodeInvalidToken() {
    #expect(SmtpEnhancedStatusCode("2.1") == nil)
    #expect(SmtpEnhancedStatusCode("2.1.x") == nil)
    #expect(SmtpEnhancedStatusCode("2..5") == nil)
}

@Test
func enhancedStatusCodesFromResponseLines() {
    let response = SmtpResponse(code: 250, lines: [
        "2.1.5 Ok",
        "SIZE 1024",
        " 2.1.0 Sender ok"
    ])

    let codes = response.enhancedStatusCodes
    #expect(codes.count == 2)
    #expect(codes.first == SmtpEnhancedStatusCode("2.1.5"))
    #expect(codes.last == SmtpEnhancedStatusCode("2.1.0"))
    #expect(response.enhancedStatusCode == SmtpEnhancedStatusCode("2.1.5"))
}
