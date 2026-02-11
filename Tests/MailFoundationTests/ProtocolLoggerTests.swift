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

import Foundation
import Testing
@testable import MailFoundation

private func memoryStreamOutput(_ stream: OutputStream) -> String {
    let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()
    return String(decoding: data, as: UTF8.self)
}

private func splitLines(_ text: String) -> [String] {
    text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
}

private func extractTimestamp(from line: String, format: String) -> (Date, String)? {
    guard let spaceIndex = line.firstIndex(of: " ") else { return nil }
    let timestampText = String(line[..<spaceIndex])
    let remainder = String(line[line.index(after: spaceIndex)...])
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    guard let date = formatter.date(from: timestampText) else { return nil }
    return (date, remainder)
}

@Test("ProtocolLogger default settings")
func protocolLoggerDefaultSettings() {
    #expect(ProtocolLogger.defaultClientPrefix == "C: ")
    #expect(ProtocolLogger.defaultServerPrefix == "S: ")

    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)

    #expect(logger.clientPrefix == "C: ")
    #expect(logger.serverPrefix == "S: ")
    #expect(logger.timestampFormat == "yyyy-MM-dd'T'HH:mm:ss'Z'")
    #expect(logger.logTimestamps == false)
    #expect(logger.redactSecrets == true)

    logger.close()
    stream.close()
}

@Test("ProtocolLogger ignores invalid log arguments")
func protocolLoggerIgnoresInvalidArguments() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)

    let buffer = Array("PING\r\n".utf8)
    logger.logClient(buffer, offset: -1, count: buffer.count)
    logger.logClient(buffer, offset: buffer.count + 1, count: 1)
    logger.logClient(buffer, offset: 0, count: buffer.count + 1)
    logger.logClient(buffer, offset: 0, count: -1)

    logger.logServer(buffer, offset: -1, count: buffer.count)
    logger.logServer(buffer, offset: buffer.count + 1, count: 1)
    logger.logServer(buffer, offset: 0, count: buffer.count + 1)
    logger.logServer(buffer, offset: 0, count: -1)

    logger.logClient(buffer, offset: 0, count: 0)
    logger.logServer(buffer, offset: 0, count: 0)

    logger.close()
    stream.close()

    let output = memoryStreamOutput(stream)
    #expect(output.isEmpty)
}

@Test("ProtocolLogger logging")
func protocolLoggerLogging() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.redactSecrets = false

    let url = URL(string: "pop://pop.skyfall.net:110/")!
    logger.logConnect(url)

    let command = Array("RETR 1\r\n".utf8)
    logger.logClient(command, offset: 0, count: command.count)

    let response = Array("+OK message\r\nLine 2\r\n".utf8)
    logger.logServer(response, offset: 0, count: response.count)

    logger.close()
    stream.close()

    let lines = splitLines(memoryStreamOutput(stream))
    #expect(lines.count == 4)
    #expect(lines[0] == "Connected to pop://pop.skyfall.net:110/")
    #expect(lines[1] == "C: RETR 1")
    #expect(lines[2] == "S: +OK message")
    #expect(lines[3] == "S: Line 2")
}

@Test("ProtocolLogger logConnect midline")
func protocolLoggerLogConnectMidline() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.redactSecrets = false

    let buffer = Array("PARTIAL LINE".utf8)
    logger.logClient(buffer, offset: 0, count: buffer.count)
    logger.logConnect(URL(string: "proto://server.com/")!)
    logger.logServer(buffer, offset: 0, count: buffer.count)
    logger.logConnect(URL(string: "proto://server.com/")!)

    logger.close()
    stream.close()

    let output = memoryStreamOutput(stream)
    let expected = "C: PARTIAL LINE\r\nConnected to proto://server.com/\r\nS: PARTIAL LINE\r\nConnected to proto://server.com/\r\n"
    #expect(output == expected)
}

@Test("ProtocolLogger logging with custom prefixes")
func protocolLoggerLoggingWithCustomPrefixes() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.clientPrefix = "C> "
    logger.serverPrefix = "S> "
    logger.redactSecrets = false

    let url = URL(string: "pop://pop.skyfall.net:110/")!
    logger.logConnect(url)

    let command = Array("RETR 1\r\n".utf8)
    logger.logClient(command, offset: 0, count: command.count)

    let response = Array("+OK message\r\nLine 2\r\n".utf8)
    logger.logServer(response, offset: 0, count: response.count)

    logger.close()
    stream.close()

    let lines = splitLines(memoryStreamOutput(stream))
    #expect(lines.count == 4)
    #expect(lines[0] == "Connected to pop://pop.skyfall.net:110/")
    #expect(lines[1] == "C> RETR 1")
    #expect(lines[2] == "S> +OK message")
    #expect(lines[3] == "S> Line 2")
}

@Test("ProtocolLogger logging with timestamps")
func protocolLoggerLoggingWithTimestamps() {
    let stream = OutputStream.toMemory()
    let logger = ProtocolLogger(stream: stream, leaveOpen: true)
    logger.logTimestamps = true
    logger.redactSecrets = false
    let format = logger.timestampFormat

    let url = URL(string: "pop://pop.skyfall.net:110/")!
    logger.logConnect(url)

    let command = Array("RETR 1\r\n".utf8)
    logger.logClient(command, offset: 0, count: command.count)

    let response = Array("+OK message\r\nLine 2\r\n".utf8)
    logger.logServer(response, offset: 0, count: response.count)

    logger.close()
    stream.close()

    let lines = splitLines(memoryStreamOutput(stream))
    #expect(lines.count == 4)

    if let (_, line) = extractTimestamp(from: lines[0], format: format) {
        #expect(line == "Connected to pop://pop.skyfall.net:110/")
    } else {
        #expect(Bool(false), "Connect timestamp")
    }

    if let (_, line) = extractTimestamp(from: lines[1], format: format) {
        #expect(line == "C: RETR 1")
    } else {
        #expect(Bool(false), "Client timestamp")
    }

    if let (_, line) = extractTimestamp(from: lines[2], format: format) {
        #expect(line == "S: +OK message")
    } else {
        #expect(Bool(false), "Server timestamp 1")
    }

    if let (_, line) = extractTimestamp(from: lines[3], format: format) {
        #expect(line == "S: Line 2")
    } else {
        #expect(Bool(false), "Server timestamp 2")
    }
}
