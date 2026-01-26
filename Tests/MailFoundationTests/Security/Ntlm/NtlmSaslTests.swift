//
// NtlmSaslTests.swift
//
// Tests for NTLM SASL integration.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("POP3 NTLM SASL creation")
func pop3NtlmSaslCreation() {
    let auth = Pop3Sasl.ntlm(username: "user", password: "password", domain: "DOMAIN")

    #expect(auth.mechanism == "NTLM")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)

    // Initial response should be base64-encoded Type 1 message
    if let response = auth.initialResponse, let data = Data(base64Encoded: response) {
        // Verify NTLMSSP signature
        #expect(data[0] == 0x4E)  // N
        #expect(data[1] == 0x54)  // T
        #expect(data[2] == 0x4C)  // L
        #expect(data[3] == 0x4D)  // M
        #expect(data[8] == 0x01)  // Type 1
    }
}

@Test("SMTP NTLM SASL creation")
func smtpNtlmSaslCreation() {
    let auth = SmtpSasl.ntlm(username: "CORP\\jsmith", password: "secret")

    #expect(auth.mechanism == "NTLM")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("IMAP NTLM SASL creation")
func imapNtlmSaslCreation() {
    let auth = ImapSasl.ntlm(username: "user@domain.com", password: "secret")

    #expect(auth.mechanism == "NTLM")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("POP3 NTLM SASL challenge response")
func pop3NtlmSaslChallengeResponse() throws {
    let auth = Pop3Sasl.ntlm(username: "user", password: "password", domain: "DOMAIN")

    // Build a minimal Type 2 challenge message
    var challengeData = Data(count: 56)
    let sig: [UInt8] = [0x4E, 0x54, 0x4C, 0x4D, 0x53, 0x53, 0x50, 0x00]
    for (i, b) in sig.enumerated() {
        challengeData[i] = b
    }
    challengeData[8] = 0x02  // Type 2
    // Flags: NegotiateUnicode | NegotiateNtlm | NegotiateExtendedSessionSecurity
    challengeData[20] = 0x01
    challengeData[21] = 0x82
    challengeData[22] = 0x08
    challengeData[23] = 0x00
    // Server challenge
    for i in 0..<8 {
        challengeData[24 + i] = UInt8(0x01 + i)
    }

    let challengeBase64 = challengeData.base64EncodedString()

    // Get response using responder
    let response = try auth.responder?(challengeBase64)
    #expect(response != nil)

    // Decode and verify it's a Type 3 message
    if let responseBase64 = response, let responseData = Data(base64Encoded: responseBase64) {
        #expect(responseData[0] == 0x4E)  // N
        #expect(responseData[1] == 0x54)  // T
        #expect(responseData[2] == 0x4C)  // L
        #expect(responseData[3] == 0x4D)  // M
        #expect(responseData[8] == 0x03)  // Type 3
    }
}

@Test("POP3 NTLM SASL invalid base64 challenge")
func pop3NtlmSaslInvalidBase64() {
    let auth = Pop3Sasl.ntlm(username: "user", password: "password")

    #expect(throws: NtlmError.invalidBase64) {
        _ = try auth.responder?("not-valid-base64!!!")
    }
}

@Test("POP3 choose authentication includes NTLM")
func pop3ChooseAuthenticationNtlm() {
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["NTLM", "PLAIN"]
    )

    // NTLM should be preferred over PLAIN (after CRAM-MD5)
    #expect(auth?.mechanism == "NTLM")
}

@Test("IMAP choose authentication includes NTLM")
func imapChooseAuthenticationNtlm() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["NTLM", "PLAIN", "LOGIN"]
    )

    #expect(auth?.mechanism == "NTLM")
}

@Test("NTLM SASL username parsing - domain in username")
func ntlmSaslUsernameParsing() {
    let auth = Pop3Sasl.ntlm(username: "CORP\\jsmith", password: "secret")

    // Decode the initial response to verify domain handling
    if let response = auth.initialResponse, let data = Data(base64Encoded: response) {
        let message = try? NtlmNegotiateMessage(data: data)
        #expect(message?.domain == "CORP")
    }
}
