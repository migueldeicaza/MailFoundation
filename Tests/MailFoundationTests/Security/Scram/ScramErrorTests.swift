//
// ScramErrorTests.swift
//
// Tests for SCRAM error types.
//

import Foundation
import Testing

@testable import MailFoundation

@Test("SCRAM error - incompleteChallenge")
func scramErrorIncompleteChallenge() {
    let error = ScramError.incompleteChallenge("missing salt")
    if case .incompleteChallenge(let msg) = error {
        #expect(msg == "missing salt")
    } else {
        Issue.record("Expected incompleteChallenge")
    }
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("missing salt"))
}

@Test("SCRAM error - invalidChallenge")
func scramErrorInvalidChallenge() {
    let error = ScramError.invalidChallenge("bad nonce")
    if case .invalidChallenge(let msg) = error {
        #expect(msg == "bad nonce")
    } else {
        Issue.record("Expected invalidChallenge")
    }
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("bad nonce"))
}

@Test("SCRAM error - incorrectHash")
func scramErrorIncorrectHash() {
    let error = ScramError.incorrectHash("signature mismatch")
    if case .incorrectHash(let msg) = error {
        #expect(msg == "signature mismatch")
    } else {
        Issue.record("Expected incorrectHash")
    }
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("signature mismatch"))
}

@Test("SCRAM error - invalidBase64")
func scramErrorInvalidBase64() {
    let error = ScramError.invalidBase64
    #expect(error == ScramError.invalidBase64)
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("base64"))
}

@Test("SCRAM error - cryptoUnavailable")
func scramErrorCryptoUnavailable() {
    let error = ScramError.cryptoUnavailable
    #expect(error == ScramError.cryptoUnavailable)
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("cryptographic"))
}

@Test("SCRAM error - alreadyAuthenticated")
func scramErrorAlreadyAuthenticated() {
    let error = ScramError.alreadyAuthenticated
    #expect(error == ScramError.alreadyAuthenticated)
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("completed"))
}

@Test("SCRAM error equatable")
func scramErrorEquatable() {
    #expect(ScramError.invalidBase64 == ScramError.invalidBase64)
    #expect(ScramError.cryptoUnavailable == ScramError.cryptoUnavailable)
    #expect(ScramError.alreadyAuthenticated == ScramError.alreadyAuthenticated)
    #expect(ScramError.invalidBase64 != ScramError.cryptoUnavailable)
    #expect(ScramError.incompleteChallenge("a") == ScramError.incompleteChallenge("a"))
    #expect(ScramError.incompleteChallenge("a") != ScramError.incompleteChallenge("b"))
}
