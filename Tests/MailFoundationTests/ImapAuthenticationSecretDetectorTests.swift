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
    detector: ImapAuthenticationSecretDetector,
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

@Test("Imap secret detector empty command")
func imapSecretDetectorEmptyCommand() {
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer: [UInt8] = []
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Imap secret detector non-auth command")
func imapSecretDetectorNonAuthCommand() {
    let command = "A00000000 APPEND INBOX (\\Seen) \"01-Jan-2026 10:00:00 +0000\" {4096}\r\n"
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Imap secret detector not authenticating")
func imapSecretDetectorNotAuthenticating() {
    let command = "A00000000 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let detector = ImapAuthenticationSecretDetector()
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)
}

@Test("Imap secret detector LOGIN command")
func imapSecretDetectorLoginCommand() {
    let command = "A00000000 LOGIN username password\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    #expect(secrets[0].startIndex == userIndex)
    #expect(secrets[0].length == 8)
    #expect(secrets[1].startIndex == passIndex)
    #expect(secrets[1].length == 8)
}

@Test("Imap secret detector LOGIN command bit-by-bit")
func imapSecretDetectorLoginCommandBitByBit() {
    let command = "A00000000 LOGIN username password\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= userIndex && index < userIndex + 8) || (index >= passIndex && index < passIndex + 8)
    }
}

@Test("Imap secret detector LOGIN command qstrings")
func imapSecretDetectorLoginCommandQStrings() {
    let command = "A00000000 LOGIN \"username\" \"password\"\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    #expect(secrets[0].startIndex == userIndex)
    #expect(secrets[0].length == 8)
    #expect(secrets[1].startIndex == passIndex)
    #expect(secrets[1].length == 8)
}

@Test("Imap secret detector LOGIN command qstrings bit-by-bit")
func imapSecretDetectorLoginCommandQStringsBitByBit() {
    let command = "A00000000 LOGIN \"username\" \"password\"\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= userIndex && index < userIndex + 8) || (index >= passIndex && index < passIndex + 8)
    }
}

@Test("Imap secret detector LOGIN command escaped qstrings")
func imapSecretDetectorLoginCommandEscapedQStrings() {
    let command = "A00000000 LOGIN \"domain\\\\username\" \"pass\\\"word\"\r\n"
    let userIndex = byteIndex(of: "domain\\\\username", in: command)
    let passIndex = byteIndex(of: "pass\\\"word", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    #expect(secrets[0].startIndex == userIndex)
    #expect(secrets[0].length == 16)
    #expect(secrets[1].startIndex == passIndex)
    #expect(secrets[1].length == 10)
}

@Test("Imap secret detector LOGIN command escaped qstrings bit-by-bit")
func imapSecretDetectorLoginCommandEscapedQStringsBitByBit() {
    let command = "A00000000 LOGIN \"domain\\\\username\" \"pass\\\"word\"\r\n"
    let userIndex = byteIndex(of: "domain\\\\username", in: command)
    let passIndex = byteIndex(of: "pass\\\"word", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= userIndex && index < userIndex + 16) || (index >= passIndex && index < passIndex + 10)
    }
}

@Test("Imap secret detector LOGIN command literals")
func imapSecretDetectorLoginCommandLiterals() {
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true

    var buffer = Array("A00000000 LOGIN {8}\r\n".utf8)
    var secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.isEmpty)

    buffer = Array("username {8}\r\n".utf8)
    secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 0)
    #expect(secrets[0].length == 8)

    buffer = Array("password\r\n".utf8)
    secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == 0)
    #expect(secrets[0].length == 8)
}

@Test("Imap secret detector LOGIN command literals bit-by-bit")
func imapSecretDetectorLoginCommandLiteralsBitByBit() {
    let command = "A00000000 LOGIN {8}\r\nusername {8}\r\npassword\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= userIndex && index < userIndex + 8) || (index >= passIndex && index < passIndex + 8)
    }
}

@Test("Imap secret detector LOGIN command literal plus")
func imapSecretDetectorLoginCommandLiteralPlus() {
    let command = "A00000000 LOGIN {8+}\r\nusername {8+}\r\npassword\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 2)
    #expect(secrets[0].startIndex == userIndex)
    #expect(secrets[0].length == 8)
    #expect(secrets[1].startIndex == passIndex)
    #expect(secrets[1].length == 8)
}

@Test("Imap secret detector LOGIN command literal plus bit-by-bit")
func imapSecretDetectorLoginCommandLiteralPlusBitByBit() {
    let command = "A00000000 LOGIN {8+}\r\nusername {8+}\r\npassword\r\n"
    let userIndex = byteIndex(of: "username", in: command)
    let passIndex = byteIndex(of: "password", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, _ in
        (index >= userIndex && index < userIndex + 8) || (index >= passIndex && index < passIndex + 8)
    }
}

@Test("Imap secret detector SASL-IR AUTHENTICATE command")
func imapSecretDetectorSaslIrAuthCommand() {
    let command = "A00000000 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    let buffer = Array(command.utf8)
    let secrets = detector.detectSecrets(in: buffer, offset: 0, count: buffer.count)
    #expect(secrets.count == 1)
    #expect(secrets[0].startIndex == secretIndex)
    #expect(secrets[0].length == 24)
}

@Test("Imap secret detector SASL-IR AUTHENTICATE command bit-by-bit")
func imapSecretDetectorSaslIrAuthCommandBitByBit() {
    let command = "A00000000 AUTHENTICATE PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n"
    let secretIndex = byteIndex(of: "AHVzZXJuYW1lAHBhc3N3b3Jk", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        index >= secretIndex && byte != 0x0D && byte != 0x0A
    }
}

@Test("Imap secret detector multi-line SASL AUTHENTICATE command")
func imapSecretDetectorMultiLineSaslAuthCommand() {
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true

    var buffer = Array("A00000000 AUTHENTICATE LOGIN\r\n".utf8)
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

@Test("Imap secret detector multi-line SASL AUTHENTICATE command bit-by-bit")
func imapSecretDetectorMultiLineSaslAuthCommandBitByBit() {
    let command = "A00000000 AUTHENTICATE LOGIN\r\ndXNlcm5hbWU=\r\ncGFzc3dvcmQ=\r\n"
    let firstIndex = byteIndex(of: "dXNlcm5hbWU=", in: command)
    let secondIndex = byteIndex(of: "cGFzc3dvcmQ=", in: command)
    let detector = ImapAuthenticationSecretDetector()
    detector.isAuthenticating = true
    assertSecretsBitByBit(command, detector: detector) { index, byte in
        guard byte != 0x0D && byte != 0x0A else { return false }
        return (index >= firstIndex && index < firstIndex + 12) || (index >= secondIndex && index < secondIndex + 12)
    }
}
