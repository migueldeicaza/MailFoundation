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
    detector: Pop3AuthenticationSecretDetector,
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

@Test("Pop3 secret detector empty command")
func pop3SecretDetectorEmptyCommand() {
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer: [UInt8] = []
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Pop3 secret detector non-auth command")
func pop3SecretDetectorNonAuthCommand() {
    let command = "UIDL 1\r\n"
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Pop3 secret detector not authenticating")
func pop3SecretDetectorNotAuthenticating() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let detector = Pop3AuthenticationSecretDetector()
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Pop3 secret detector APOP command")
func pop3SecretDetectorApopCommand() {
    let command = "APOP username AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let tokenIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    #expect(secrets[0].startIndex == userIndex)
    #expect(secrets[0].length == 8)
    #expect(secrets[1].startIndex == tokenIndex)
    #expect(secrets[1].length == 24)
}

@Test("Pop3 secret detector APOP command bit-by-bit")
func pop3SecretDetectorApopCommandBitByBit() {
    let command = "APOP username AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let commandLength = command.utf8.count
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        index >= 5 && index != 13 && index < commandLength - 2
    }
}

@Test("Pop3 secret detector USER/PASS command")
func pop3SecretDetectorUserPassCommand() {
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true

    var buffer = Array("USER user\r\n".utf8)
    var secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 5)
    #expect(secrets[0].length == 4)

    buffer = Array("PASS p@$$w0rd\r\n".utf8)
    secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 5)
    #expect(secrets[0].length == 8)
}

@Test("Pop3 secret detector USER/PASS command bit-by-bit")
func pop3SecretDetectorUserPassCommandBitByBit() {
    let command = "USER user\r\nPASS p@$$w0rd\r\n"
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= 5 && index < 9) || (index >= 16 && index < 24)
    }
}

@Test("Pop3 secret detector SASL-IR AUTH")
func pop3SecretDetectorSaslIrAuthCommand() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == secretIndex)
    #expect(secrets[0].length == 24)
}

@Test("Pop3 secret detector SASL-IR AUTH bit-by-bit")
func pop3SecretDetectorSaslIrAuthCommandBitByBit() {
    let command = "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        index >= secretIndex && byte != 0x0D && byte != 0x0A
    }
}

@Test("Pop3 secret detector multi-line SASL AUTH")
func pop3SecretDetectorMultiLineSaslAuthCommand() {
    let detector = Pop3AuthenticationSecretDetector()
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

@Test("Pop3 secret detector multi-line SASL AUTH bit-by-bit")
func pop3SecretDetectorMultiLineSaslAuthCommandBitByBit() {
    let command = "AUTH LOGIN\r\ndXNlcm5hbWU=\r\ncGFzc3dvcmQ=\r\n"
    let secretIndex = byteIndex(of: "dXNlcm5hbWU=", in: command)
    let detector = Pop3AuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        index >= secretIndex && byte != 0x0D && byte != 0x0A
    }
}
