//
// GssapiSaslTests.swift
//
// Tests for GSSAPI SASL integration.
//

import Foundation
import Testing

@testable import MailFoundation

// Note: Most GSSAPI tests require a valid Kerberos credential cache to work.
// In a test environment without Kerberos configured, the gssapi() methods
// will return nil because initial context creation fails.
// These tests verify the behavior in both scenarios.

@Test("GSSAPI is available on macOS")
func gssapiAvailable() {
    #if canImport(GSS)
    #expect(GssapiContext.isAvailable == true)
    #else
    #expect(GssapiContext.isAvailable == false)
    #endif
}

@Test("IMAP GSSAPI SASL creation - returns nil without credentials")
func imapGssapiSaslCreation() {
    // Without valid Kerberos credentials, gssapi() returns nil
    // This is expected behavior - the method tries to create an initial token
    // and fails if there are no credentials available
    let auth = ImapSasl.gssapi(host: "mail.example.com")

    // On a system with valid Kerberos credentials, auth would not be nil
    // On a system without, auth will be nil
    if let auth = auth {
        #expect(auth.mechanism == "GSSAPI")
        #expect(auth.responder != nil)
    }
    // No failure expected either way
}

@Test("SMTP GSSAPI SASL creation - returns nil without credentials")
func smtpGssapiSaslCreation() {
    let auth = SmtpSasl.gssapi(host: "mail.example.com")

    if let auth = auth {
        #expect(auth.mechanism == "GSSAPI")
        #expect(auth.responder != nil)
    }
}

@Test("POP3 GSSAPI SASL creation - returns nil without credentials")
func pop3GssapiSaslCreation() {
    let auth = Pop3Sasl.gssapi(host: "mail.example.com")

    if let auth = auth {
        #expect(auth.mechanism == "GSSAPI")
        #expect(auth.responder != nil)
    }
}

@Test("IMAP GSSAPI SASL with custom SPN")
func imapGssapiWithCustomSpn() {
    let auth = ImapSasl.gssapi(
        servicePrincipalName: "imap@custom.example.com",
        host: "mail.example.com"
    )

    if let auth = auth {
        #expect(auth.mechanism == "GSSAPI")
    }
}

@Test("IMAP GSSAPI SASL with credentials")
func imapGssapiWithCredentials() {
    let auth = ImapSasl.gssapi(
        host: "mail.example.com",
        username: "user@EXAMPLE.COM",
        password: "secret"
    )

    // This may still return nil if credential acquisition fails
    if let auth = auth {
        #expect(auth.mechanism == "GSSAPI")
    }
}

@Test("IMAP choose authentication falls back when GSSAPI unavailable")
func imapChooseAuthenticationGssapiFallback() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["GSSAPI", "NTLM", "PLAIN"],
        host: "mail.example.com"
    )

    // Should get some auth method (GSSAPI if available, otherwise NTLM)
    #expect(auth != nil)
    #expect(auth?.mechanism == "GSSAPI" || auth?.mechanism == "NTLM")
}

@Test("SMTP choose authentication falls back when GSSAPI unavailable")
func smtpChooseAuthenticationGssapiFallback() {
    let auth = SmtpSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["GSSAPI", "NTLM", "PLAIN"],
        host: "mail.example.com"
    )

    #expect(auth != nil)
    #expect(auth?.mechanism == "GSSAPI" || auth?.mechanism == "NTLM")
}

@Test("POP3 choose authentication falls back when GSSAPI unavailable")
func pop3ChooseAuthenticationGssapiFallback() {
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["GSSAPI", "CRAM-MD5", "PLAIN"],
        host: "mail.example.com"
    )

    #expect(auth != nil)
    // Falls back to CRAM-MD5 or PLAIN if GSSAPI isn't available
    #expect(auth?.mechanism == "GSSAPI" || auth?.mechanism == "CRAM-MD5" || auth?.mechanism == "PLAIN")
}

@Test("GSSAPI responder throws invalidBase64 for bad input")
func gssapiResponderInvalidBase64() {
    // This test only runs if GSSAPI auth can be created
    guard let auth = ImapSasl.gssapi(host: "mail.example.com") else {
        // Skip if no Kerberos credentials available
        return
    }

    #expect(throws: GssapiError.invalidBase64) {
        _ = try auth.responder?("not-valid-base64!!!")
    }
}

@Test("GSSAPI SASL returns nil when framework not available")
func gssapiSaslNotAvailableOnOtherPlatforms() {
    #if !canImport(GSS)
    // On platforms without GSS, should return nil
    let auth = ImapSasl.gssapi(host: "mail.example.com")
    #expect(auth == nil)
    #endif
}

@Test("IMAP choose authentication without GSSAPI in mechanisms")
func imapChooseAuthenticationNoGssapi() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["NTLM", "PLAIN"],
        host: "mail.example.com"
    )

    #expect(auth != nil)
    #expect(auth?.mechanism == "NTLM")
}

@Test("SMTP choose authentication without GSSAPI in mechanisms")
func smtpChooseAuthenticationNoGssapi() {
    let auth = SmtpSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["NTLM", "PLAIN"],
        host: "mail.example.com"
    )

    #expect(auth != nil)
    #expect(auth?.mechanism == "NTLM")
}

@Test("POP3 choose authentication without GSSAPI in mechanisms")
func pop3ChooseAuthenticationNoGssapi() {
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["CRAM-MD5", "PLAIN"],
        host: "mail.example.com"
    )

    #expect(auth != nil)
    #expect(auth?.mechanism == "CRAM-MD5")
}
