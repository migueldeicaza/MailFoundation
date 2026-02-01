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
@testable import MailFoundation

private func loadReplayFixture(_ relativePath: String) -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(relativePath)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Missing fixture: \(relativePath)")
    }
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n", with: "\r\n")
    return normalized
}

private func extractTag(from command: String) -> String? {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let firstSpace = trimmed.firstIndex(of: " ") else {
        return nil
    }
    return String(trimmed[..<firstSpace])
}

struct ImapReplayStep {
    let expectedCommand: String?
    let response: [UInt8]

    static func greeting(_ fixture: String) -> ImapReplayStep {
        let text = loadReplayFixture(fixture)
        return ImapReplayStep(expectedCommand: nil, response: Array(text.utf8))
    }

    static func serverPush(_ fixture: String) -> ImapReplayStep {
        let text = loadReplayFixture(fixture)
        return ImapReplayStep(expectedCommand: nil, response: Array(text.utf8))
    }

    static func command(_ command: String, fixture: String, responseTag: String? = nil) -> ImapReplayStep {
        let tag = responseTag ?? extractTag(from: command)
        var text = loadReplayFixture(fixture)
        if let tag {
            text = text.replacingOccurrences(of: "A########", with: tag)
        }
        return ImapReplayStep(expectedCommand: command, response: Array(text.utf8))
    }
}

final class ImapReplayTransport: Transport, CompressionTransport {
    private var steps: [ImapReplayStep]
    private var stepIndex = 0
    private var readyToRespond = false

    var written: [[UInt8]] = []
    var failures: [String] = []
    var compressionStarted = false
    var compressionAlgorithm: String?

    init(steps: [ImapReplayStep]) {
        self.steps = steps
        if let first = steps.first, first.expectedCommand == nil {
            readyToRespond = true
        }
    }

    func open() {}
    func close() {}

    func write(_ bytes: [UInt8]) -> Int {
        written.append(bytes)

        guard stepIndex < steps.count else {
            failures.append("Unexpected write: \(String(decoding: bytes, as: UTF8.self))")
            return bytes.count
        }

        let step = steps[stepIndex]
        guard let expected = step.expectedCommand else {
            failures.append("Unexpected write before server response: \(String(decoding: bytes, as: UTF8.self))")
            return bytes.count
        }

        let actual = String(decoding: bytes, as: UTF8.self)
        if actual != expected {
            failures.append("Expected command \(expected) but got \(actual)")
        }
        readyToRespond = true
        return bytes.count
    }

    func readAvailable(maxLength: Int) -> [UInt8] {
        guard stepIndex < steps.count else { return [] }
        let step = steps[stepIndex]
        if step.expectedCommand != nil && !readyToRespond {
            return []
        }
        stepIndex += 1
        readyToRespond = stepIndex < steps.count && steps[stepIndex].expectedCommand == nil
        return step.response
    }

    func startCompression(algorithm: String) throws {
        compressionStarted = true
        compressionAlgorithm = algorithm
    }
}
