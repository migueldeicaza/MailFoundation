//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Testing
@testable import MailFoundation

private func byteIndex(of substring: String, in command: String) -> Int {
    guard let range = command.range(of: substring),
          let start = range.lowerBound.samePosition(in: command.utf8) else {
        #expect(Bool(false), "Missing substring \(substring)")
        return 0
    }
    return command.utf8.distance(from: command.utf8.startIndex, to: start)
}

private func assertSecretsBitByBit(
    _ command: String,
    detector: SmtpAuthenticationSecretDetector,
    expectsSecretAt: (Int, UInt8) -> Bool
) {
    let buffer = Array(command.utf8)
    for index in 0..<buffer.count {
        let secrets = detector.detectSecrets(in: buffer, offset: index, count: 1)
        if expectsSecretAt(index, buffer[index]) {
            #expect(secrets.count == 1, "# of secrets @ index \(index)")
            #expect(secrets.first?.startIndex == index, "StartIndex")
            #expect(secrets.first?.length == 1, "Length")
        } else {
            #expect(secrets.isEmpty, "# of secrets @ index \(index)")
        }
    }
}

@Test("Smtp secret detector empty command")
func smtpSecretDetectorEmptyCommand() {
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer: [UInt8] = []
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Smtp secret detector non-auth command")
func smtpSecretDetectorNonAuthCommand() {
    let command = "MAIL FROM:<user@domain.com>\r\n"
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Smtp secret detector not authenticating")
func smtpSecretDetectorNotAuthenticating() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let detector = SmtpAuthenticationSecretDetector()
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Smtp secret detector SASL-IR AUTH")
func smtpSecretDetectorSaslIrAuthCommand() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == secretIndex)
    #expect(secrets[0].length == 24)
}

@Test("Smtp secret detector SASL-IR AUTH bit-by-bit")
func smtpSecretDetectorSaslIrAuthCommandBitByBit() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        index >= secretIndex && byte != 0x0D && byte != 0x0A
    }
}

@Test("Smtp secret detector multi-line SASL AUTH")
func smtpSecretDetectorMultiLineSaslAuthCommand() {
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true

    var buffer = Array("AUTH LOGIN\r\n".utf8)
    var secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)

    buffer = Array("dXNlcm5hbWU=\r\n".utf8)
    secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 0)
    #expect(secrets[0].length == 12)

    buffer = Array("cGFzc3dvcmQ=\r\n".utf8)
    secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 0)
    #expect(secrets[0].length == 12)
}

@Test("Smtp secret detector multi-line SASL AUTH bit-by-bit")
func smtpSecretDetectorMultiLineSaslAuthCommandBitByBit() {
    let command = "AUTH LOGIN\r\ndXNlcm5hbWU=\r\ncGFzc3dvcmQ=\r\n"
    let secretIndex = byteIndex(of: "dXNlcm5hbWU=", in: command)
    let detector = SmtpAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        index >= secretIndex && byte != 0x0D && byte != 0x0A
    }
}
