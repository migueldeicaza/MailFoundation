//
// GssapiContextTests.swift
//
// Tests for GSSAPI context.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("GSSAPI context availability")
func gssapiContextAvailability() {
    // On macOS/iOS, GSSAPI should be available
    #if canImport(GSS)
    #expect(GssapiContext.isAvailable == true)
    #else
    #expect(GssapiContext.isAvailable == false)
    #endif
}

@Test("GSSAPI context creation")
func gssapiContextCreation() {
    let context = GssapiContext(
        servicePrincipalName: "imap@mail.example.com",
        username: "user@EXAMPLE.COM",
        password: "secret"
    )

    #expect(context.servicePrincipalName == "imap@mail.example.com")
    #expect(context.username == "user@EXAMPLE.COM")
    #expect(context.isComplete == false)
    #expect(context.negotiatedSecurityLayer == false)
}

@Test("GSSAPI context default values")
func gssapiContextDefaultValues() {
    let context = GssapiContext(servicePrincipalName: "smtp@mail.example.com")

    #expect(context.servicePrincipalName == "smtp@mail.example.com")
    #expect(context.username == nil)
    #expect(context.isComplete == false)
    #expect(context.negotiatedSecurityLayer == false)
    #expect(context.desiredSecurityLayer == .none)
    #expect(context.maxMessageSize == 0)
}

@Test("GSSAPI context reset")
func gssapiContextReset() {
    let context = GssapiContext(servicePrincipalName: "imap@mail.example.com")

    // Reset should not throw and should keep isComplete false
    context.reset()
    #expect(context.isComplete == false)
    #expect(context.negotiatedSecurityLayer == false)
}

@Test("GSSAPI security layer options")
func gssapiSecurityLayerOptions() {
    #expect(GssapiSecurityLayer.none.rawValue == 0x01)
    #expect(GssapiSecurityLayer.integrity.rawValue == 0x02)
    #expect(GssapiSecurityLayer.confidentiality.rawValue == 0x04)

    // Test OptionSet behavior
    let combined: GssapiSecurityLayer = [.integrity, .confidentiality]
    #expect(combined.contains(.integrity))
    #expect(combined.contains(.confidentiality))
    #expect(!combined.contains(.none))
}

@Test("GSSAPI context wrap without auth throws")
func gssapiContextWrapWithoutAuth() {
    let context = GssapiContext(servicePrincipalName: "imap@mail.example.com")
    let message = Data("test".utf8)

    #expect(throws: GssapiError.authenticationIncomplete) {
        _ = try context.wrap(message: message)
    }
}

@Test("GSSAPI context unwrap without auth throws")
func gssapiContextUnwrapWithoutAuth() {
    let context = GssapiContext(servicePrincipalName: "imap@mail.example.com")
    let message = Data("test".utf8)

    #expect(throws: GssapiError.authenticationIncomplete) {
        _ = try context.unwrap(message: message)
    }
}

@Test("GSSAPI context negotiate security layer without auth throws")
func gssapiContextNegotiateWithoutAuth() {
    let context = GssapiContext(servicePrincipalName: "imap@mail.example.com")
    let challenge = Data([0x01, 0x00, 0x00, 0x00])

    #expect(throws: GssapiError.authenticationIncomplete) {
        _ = try context.negotiateSecurityLayer(challenge: challenge)
    }
}
