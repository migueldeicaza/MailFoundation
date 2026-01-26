//
// ScramSaslTests.swift
//
// Tests for SCRAM SASL integration.
//

import Foundation
import Testing

@testable import MailFoundation

// MARK: - IMAP SCRAM SASL Tests

@Test("IMAP SCRAM-SHA-1 creation")
func imapScramSha1Creation() {
    let auth = ImapSasl.scramSha1(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-1")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("IMAP SCRAM-SHA-256 creation")
func imapScramSha256Creation() {
    let auth = ImapSasl.scramSha256(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-256")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("IMAP SCRAM-SHA-512 creation")
func imapScramSha512Creation() {
    let auth = ImapSasl.scramSha512(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-512")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("IMAP choose authentication prefers SCRAM-SHA-512")
func imapChooseAuthenticationScramSha512() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256", "SCRAM-SHA-512"]
    )
    #expect(auth != nil)
    #expect(auth?.mechanism == "SCRAM-SHA-512")
}

@Test("IMAP choose authentication prefers SCRAM-SHA-256 over SHA-1")
func imapChooseAuthenticationScramSha256() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256"]
    )
    #expect(auth != nil)
    #expect(auth?.mechanism == "SCRAM-SHA-256")
}

@Test("IMAP choose authentication falls back to SCRAM-SHA-1")
func imapChooseAuthenticationScramSha1() {
    let auth = ImapSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["PLAIN", "SCRAM-SHA-1"]
    )
    #expect(auth != nil)
    #expect(auth?.mechanism == "SCRAM-SHA-1")
}

// MARK: - SMTP SCRAM SASL Tests

@Test("SMTP SCRAM-SHA-1 creation")
func smtpScramSha1Creation() {
    let auth = SmtpSasl.scramSha1(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-1")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("SMTP SCRAM-SHA-256 creation")
func smtpScramSha256Creation() {
    let auth = SmtpSasl.scramSha256(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-256")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("SMTP SCRAM-SHA-512 creation")
func smtpScramSha512Creation() {
    let auth = SmtpSasl.scramSha512(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-512")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("SMTP choose authentication prefers SCRAM-SHA-512")
func smtpChooseAuthenticationScramSha512() {
    let auth = SmtpSasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256", "SCRAM-SHA-512"]
    )
    #expect(auth != nil)
    #expect(auth?.mechanism == "SCRAM-SHA-512")
}

// MARK: - POP3 SCRAM SASL Tests

@Test("POP3 SCRAM-SHA-1 creation")
func pop3ScramSha1Creation() {
    let auth = Pop3Sasl.scramSha1(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-1")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("POP3 SCRAM-SHA-256 creation")
func pop3ScramSha256Creation() {
    let auth = Pop3Sasl.scramSha256(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-256")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("POP3 SCRAM-SHA-512 creation")
func pop3ScramSha512Creation() {
    let auth = Pop3Sasl.scramSha512(username: "user", password: "pencil")
    #expect(auth.mechanism == "SCRAM-SHA-512")
    #expect(auth.initialResponse != nil)
    #expect(auth.responder != nil)
}

@Test("POP3 choose authentication prefers SCRAM-SHA-512")
func pop3ChooseAuthenticationScramSha512() {
    let auth = Pop3Sasl.chooseAuthentication(
        username: "user",
        password: "password",
        mechanisms: ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256", "SCRAM-SHA-512"]
    )
    #expect(auth != nil)
    #expect(auth?.mechanism == "SCRAM-SHA-512")
}

// MARK: - SCRAM Responder Integration Tests

@Test("IMAP SCRAM-SHA-256 responder handles challenge")
func imapScramResponderHandlesChallenge() throws {
    // Create auth with known cnonce for testing
    let state = ScramSaslState(
        username: "user",
        password: "pencil",
        algorithm: .sha256,
        authorizationId: nil
    )
    state.context.cnonce = "rOprNGfwEbeRWgbNEkqO"

    // Generate initial message
    let initial = try state.context.getInitialMessage()
    let initialStr = String(data: initial, encoding: .utf8)!
    #expect(initialStr == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")

    // Server first challenge (base64 encoded)
    let serverFirst = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
    let serverFirstBase64 = Data(serverFirst.utf8).base64EncodedString()

    let response = try state.processChallenge(serverFirstBase64)
    let responseData = Data(base64Encoded: response)!
    let responseStr = String(data: responseData, encoding: .utf8)!
    #expect(responseStr == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")

    // Server final (base64 encoded)
    let serverFinal = "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="
    let serverFinalBase64 = Data(serverFinal.utf8).base64EncodedString()

    let finalResponse = try state.processChallenge(serverFinalBase64)
    #expect(finalResponse == "")
    #expect(state.context.isAuthenticated == true)
}

@Test("SCRAM responder throws on invalid base64")
func scramResponderThrowsOnInvalidBase64() {
    let state = ScramSaslState(
        username: "user",
        password: "pass",
        algorithm: .sha256,
        authorizationId: nil
    )
    _ = try? state.context.getInitialMessage()

    #expect(throws: ScramError.invalidBase64) {
        _ = try state.processChallenge("not-valid-base64!!!")
    }
}

// MARK: - Algorithm Enum Tests

@Test("ScramHashAlgorithm mechanism names")
func scramHashAlgorithmMechanismNames() {
    #expect(ScramHashAlgorithm.sha1.mechanismName == "SCRAM-SHA-1")
    #expect(ScramHashAlgorithm.sha256.mechanismName == "SCRAM-SHA-256")
    #expect(ScramHashAlgorithm.sha512.mechanismName == "SCRAM-SHA-512")
}
