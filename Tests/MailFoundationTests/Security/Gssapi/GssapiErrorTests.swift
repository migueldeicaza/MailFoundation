//
// GssapiErrorTests.swift
//
// Tests for GSSAPI error types.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("GSSAPI error - notAvailable")
func gssapiErrorNotAvailable() {
    let error = GssapiError.notAvailable
    #expect(error == GssapiError.notAvailable)
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("not available"))
}

@Test("GSSAPI error - credentialAcquisitionFailed")
func gssapiErrorCredentialAcquisitionFailed() {
    let error = GssapiError.credentialAcquisitionFailed("test message")
    if case .credentialAcquisitionFailed(let msg) = error {
        #expect(msg == "test message")
    } else {
        Issue.record("Expected credentialAcquisitionFailed")
    }
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("test message"))
}

@Test("GSSAPI error - contextInitFailed")
func gssapiErrorContextInitFailed() {
    let error = GssapiError.contextInitFailed("init error")
    if case .contextInitFailed(let msg) = error {
        #expect(msg == "init error")
    } else {
        Issue.record("Expected contextInitFailed")
    }
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - invalidToken")
func gssapiErrorInvalidToken() {
    let error = GssapiError.invalidToken
    #expect(error == GssapiError.invalidToken)
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - invalidBase64")
func gssapiErrorInvalidBase64() {
    let error = GssapiError.invalidBase64
    #expect(error == GssapiError.invalidBase64)
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - securityLayerNegotiationFailed")
func gssapiErrorSecurityLayerNegotiationFailed() {
    let error = GssapiError.securityLayerNegotiationFailed
    #expect(error == GssapiError.securityLayerNegotiationFailed)
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - securityLayerNotSupported")
func gssapiErrorSecurityLayerNotSupported() {
    let error = GssapiError.securityLayerNotSupported
    #expect(error == GssapiError.securityLayerNotSupported)
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - wrapFailed")
func gssapiErrorWrapFailed() {
    let error = GssapiError.wrapFailed("wrap error")
    if case .wrapFailed(let msg) = error {
        #expect(msg == "wrap error")
    } else {
        Issue.record("Expected wrapFailed")
    }
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - authenticationIncomplete")
func gssapiErrorAuthenticationIncomplete() {
    let error = GssapiError.authenticationIncomplete
    #expect(error == GssapiError.authenticationIncomplete)
    #expect(error.errorDescription != nil)
}

@Test("GSSAPI error - gssError")
func gssapiErrorGssError() {
    let error = GssapiError.gssError(major: 123, minor: 456, message: "GSS error")
    if case .gssError(let major, let minor, let msg) = error {
        #expect(major == 123)
        #expect(minor == 456)
        #expect(msg == "GSS error")
    } else {
        Issue.record("Expected gssError")
    }
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("123"))
    #expect(error.errorDescription!.contains("456"))
}

@Test("GSSAPI error equatable")
func gssapiErrorEquatable() {
    #expect(GssapiError.notAvailable == GssapiError.notAvailable)
    #expect(GssapiError.invalidToken == GssapiError.invalidToken)
    #expect(GssapiError.invalidBase64 == GssapiError.invalidBase64)
    #expect(GssapiError.notAvailable != GssapiError.invalidToken)
    #expect(GssapiError.credentialAcquisitionFailed("a") == GssapiError.credentialAcquisitionFailed("a"))
    #expect(GssapiError.credentialAcquisitionFailed("a") != GssapiError.credentialAcquisitionFailed("b"))
}
