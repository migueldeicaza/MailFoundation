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

struct AsyncImapSessionFailureTests {

    @Test("Async IMAP session throws when selecting without authentication")
    func asyncImapSessionOperationsWithoutAuthentication() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        // Try to select without logging in
        let selectTask = Task { try await session.select(mailbox: "INBOX") }
        
        do {
            _ = try await selectTask.value
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as SessionError {
            if case .invalidImapState(let expected, let actual) = error {
                #expect(expected == .authenticated)
                #expect(actual == .connected)
            } else {
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Async IMAP session throws when searching without selection")
    func asyncImapSessionOperationsWithoutSelection() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(message: "completed"))
        _ = try await loginTask.value

        // Try to search without selecting a mailbox
        let searchTask = Task { try await session.search("ALL") }

        do {
            _ = try await searchTask.value
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as SessionError {
            if case .invalidImapState(let expected, let actual) = error {
                #expect(expected == .selected)
                #expect(actual == .authenticated)
            } else {
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Async IMAP session handles SELECT failure")
    func asyncImapSessionSelectFailure() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(message: "completed"))
        _ = try await loginTask.value

        let selectTask = Task { try await session.select(mailbox: "NonExistent") }
        await transport.yieldIncoming(Array("A0002 NO [NONEXISTENT] Unknown Mailbox\r\n".utf8))
        
        do {
            _ = try await selectTask.value
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as SessionError {
            if case .imapError(let status, _) = error {
                #expect(status == .no)
            } else {
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
        
        #expect(await session.selectedMailbox == nil)
    }

    @Test("Async IMAP session IDLE not supported")
    func asyncImapSessionIdleNotSupported() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "AUTH=PLAIN"]))
        _ = try await loginTask.value

        let examineTask = Task { try await session.examine(mailbox: "INBOX") }
        await transport.yieldIncoming(Array("* 1 EXISTS\r\n".utf8))
        await transport.yieldIncoming(Array("A0002 OK EXAMINE\r\n".utf8))
        _ = try await examineTask.value

        do {
            _ = try await session.startIdle()
            #expect(Bool(false), "Should have thrown idleNotSupported")
        } catch let error as SessionError {
            #expect(error == .idleNotSupported)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Async IMAP session NOTIFY not supported")
    func asyncImapSessionNotifyNotSupported() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(ImapTestFixtures.loginOk(capabilities: ["IMAP4rev1", "IDLE", "AUTH=PLAIN"]))
        _ = try await loginTask.value

        do {
            _ = try await session.notify(arguments: "NONE")
            #expect(Bool(false), "Should have thrown notifyNotSupported")
        } catch let error as SessionError {
            #expect(error == .notifyNotSupported)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Async IMAP session handles protocol error")
    func asyncImapSessionProtocolError() async throws {
        let transport = AsyncStreamTransport()
        let session = AsyncImapSession(transport: transport)

        let connectTask = Task { try await session.connect() }
        await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))
        _ = try await connectTask.value

        let loginTask = Task { try await session.login(user: "user", password: "pass") }
        await transport.yieldIncoming(Array("A0001 BAD Invalid command arguments\r\n".utf8))
        
        // login returns response?, so it might return the BAD response or throw depending on implementation.
        // Checking implementation: 
        // public func login(...) async throws -> ImapResponse? {
        //     let command = try await send(.login(user, password))
        //     let response = await waitForTagged(command.tag)
        //     if response?.status == .ok { state = .authenticated } ...
        //     return response
        // }
        // It returns the response, it doesn't throw for BAD/NO.
        
        let response = try await loginTask.value
        #expect(response?.status == .bad)
        #expect(await session.isAuthenticated == false)
    }
}
