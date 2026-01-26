//
// ScramContextTests.swift
//
// Tests for SCRAM context with known test vectors.
//

import Foundation
import Testing

@testable import MailFoundation

// MARK: - SCRAM-SHA-1 Tests (RFC 5802)

@Test("SCRAM-SHA-1 full authentication flow")
func scramSha1FullAuthentication() throws {
    // Test vectors from RFC 5802 / MailKit
    let context = ScramContext(
        username: "user",
        password: "pencil",
        algorithm: .sha1
    )
    context.cnonce = "fyko+d2lbbFgONRv9qkxdawL"

    // Get initial message
    let initialData = try context.getInitialMessage()
    let initialMessage = String(data: initialData, encoding: .utf8)!
    #expect(initialMessage == "n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL")

    // Server first message
    let serverFirst = "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096"
    let responseData = try context.processChallenge(Data(serverFirst.utf8))
    let response = String(data: responseData, encoding: .utf8)!
    #expect(response == "c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,p=v0X8v3Bz2T0CJGbJQyF0X+HI4Ts=")

    // Server final message
    let serverFinal = "v=rmF9pqV8S7suAoZWja4dJRkFsKQ="
    try context.verifyServerSignature(Data(serverFinal.utf8))
    #expect(context.isAuthenticated == true)
}

// MARK: - SCRAM-SHA-256 Tests (RFC 7677)

@Test("SCRAM-SHA-256 full authentication flow")
func scramSha256FullAuthentication() throws {
    // Test vectors from MailKit tests
    let context = ScramContext(
        username: "user",
        password: "pencil",
        algorithm: .sha256
    )
    context.cnonce = "rOprNGfwEbeRWgbNEkqO"

    // Get initial message
    let initialData = try context.getInitialMessage()
    let initialMessage = String(data: initialData, encoding: .utf8)!
    #expect(initialMessage == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")

    // Server first message
    let serverFirst = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
    let responseData = try context.processChallenge(Data(serverFirst.utf8))
    let response = String(data: responseData, encoding: .utf8)!
    #expect(response == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")

    // Server final message
    let serverFinal = "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="
    try context.verifyServerSignature(Data(serverFinal.utf8))
    #expect(context.isAuthenticated == true)
}

// MARK: - Context State Tests

@Test("SCRAM context creation")
func scramContextCreation() {
    let context = ScramContext(
        username: "testuser",
        password: "testpass",
        algorithm: .sha256
    )

    #expect(context.username == "testuser")
    #expect(context.algorithm == .sha256)
    #expect(context.isAuthenticated == false)
    #expect(context.mechanismName == "SCRAM-SHA-256")
}

@Test("SCRAM context mechanism names")
func scramContextMechanismNames() {
    let sha1 = ScramContext(username: "u", password: "p", algorithm: .sha1)
    let sha256 = ScramContext(username: "u", password: "p", algorithm: .sha256)
    let sha512 = ScramContext(username: "u", password: "p", algorithm: .sha512)

    #expect(sha1.mechanismName == "SCRAM-SHA-1")
    #expect(sha256.mechanismName == "SCRAM-SHA-256")
    #expect(sha512.mechanismName == "SCRAM-SHA-512")
}

@Test("SCRAM context reset")
func scramContextReset() throws {
    let context = ScramContext(
        username: "user",
        password: "pencil",
        algorithm: .sha256
    )
    context.cnonce = "test"

    // Start authentication
    _ = try context.getInitialMessage()

    // Reset
    context.reset()
    #expect(context.isAuthenticated == false)

    // Should be able to start again
    context.cnonce = "newtest"
    let msg = try context.getInitialMessage()
    #expect(String(data: msg, encoding: .utf8)!.contains("newtest"))
}

// MARK: - Error Cases

@Test("SCRAM missing salt throws incompleteChallenge")
func scramMissingSalt() throws {
    let context = ScramContext(username: "user", password: "pass", algorithm: .sha256)
    context.cnonce = "test"
    _ = try context.getInitialMessage()

    let noSalt = "r=testnonce,i=4096"
    #expect(throws: ScramError.self) {
        _ = try context.processChallenge(Data(noSalt.utf8))
    }
}

@Test("SCRAM missing nonce throws incompleteChallenge")
func scramMissingNonce() throws {
    let context = ScramContext(username: "user", password: "pass", algorithm: .sha256)
    context.cnonce = "test"
    _ = try context.getInitialMessage()

    let noNonce = "s=c2FsdA==,i=4096"
    #expect(throws: ScramError.self) {
        _ = try context.processChallenge(Data(noNonce.utf8))
    }
}

@Test("SCRAM missing iterations throws incompleteChallenge")
func scramMissingIterations() throws {
    let context = ScramContext(username: "user", password: "pass", algorithm: .sha256)
    context.cnonce = "test"
    _ = try context.getInitialMessage()

    let noIterations = "r=testnonce,s=c2FsdA=="
    #expect(throws: ScramError.self) {
        _ = try context.processChallenge(Data(noIterations.utf8))
    }
}

@Test("SCRAM invalid nonce throws invalidChallenge")
func scramInvalidNonce() throws {
    let context = ScramContext(username: "user", password: "pass", algorithm: .sha256)
    context.cnonce = "clientnonce"
    _ = try context.getInitialMessage()

    // Server nonce doesn't start with client nonce
    let badNonce = "r=wrongnonce,s=c2FsdA==,i=4096"
    #expect(throws: ScramError.self) {
        _ = try context.processChallenge(Data(badNonce.utf8))
    }
}

@Test("SCRAM invalid signature throws incorrectHash")
func scramInvalidSignature() throws {
    let context = ScramContext(username: "user", password: "pencil", algorithm: .sha256)
    context.cnonce = "rOprNGfwEbeRWgbNEkqO"
    _ = try context.getInitialMessage()

    let serverFirst = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
    _ = try context.processChallenge(Data(serverFirst.utf8))

    // Wrong signature
    let badSignature = "v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    do {
        try context.verifyServerSignature(Data(badSignature.utf8))
        Issue.record("Expected incorrectHash error")
    } catch let error as ScramError {
        if case .incorrectHash = error {
            // Expected
        } else {
            Issue.record("Expected incorrectHash, got \(error)")
        }
    }
}

@Test("SCRAM server final without v= throws invalidChallenge")
func scramServerFinalMissingPrefix() throws {
    let context = ScramContext(username: "user", password: "pencil", algorithm: .sha256)
    context.cnonce = "rOprNGfwEbeRWgbNEkqO"
    _ = try context.getInitialMessage()

    let serverFirst = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
    _ = try context.processChallenge(Data(serverFirst.utf8))

    // Missing v= prefix
    let badFinal = "x=something"
    do {
        try context.verifyServerSignature(Data(badFinal.utf8))
        Issue.record("Expected invalidChallenge error")
    } catch let error as ScramError {
        if case .invalidChallenge = error {
            // Expected
        } else {
            Issue.record("Expected invalidChallenge, got \(error)")
        }
    }
}

// MARK: - Username Normalization

@Test("SCRAM normalizes special characters in username")
func scramUsernameNormalization() throws {
    // Test that = and , are properly escaped
    let context = ScramContext(
        username: "user=test,name",
        password: "pass",
        algorithm: .sha256
    )
    context.cnonce = "test"

    let msg = try context.getInitialMessage()
    let msgStr = String(data: msg, encoding: .utf8)!

    // = should become =3D, , should become =2C
    #expect(msgStr.contains("n=user=3Dtest=2Cname"))
}
