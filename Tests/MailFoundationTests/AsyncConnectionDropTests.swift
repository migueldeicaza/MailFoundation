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
import Foundation
@testable import MailFoundation

struct AsyncConnectionDropTests {

            @Test("Async IMAP session handles unexpected connection drop during command")

            func asyncImapConnectionDrop() async throws {

                let transport = AsyncStreamTransport()

                let session = AsyncImapSession(transport: transport, timeoutMilliseconds: 500) // Short timeout

        

                // Connect and login

                let connectTask = Task { try await session.connect() }

                await transport.yieldIncoming(Array("* OK Ready\r\n".utf8))

                _ = try await connectTask.value

        

                let loginTask = Task { try await session.login(user: "user", password: "pass") }

                await transport.yieldIncoming(ImapTestFixtures.loginOk(message: "completed"))

                _ = try await loginTask.value

        

                // Start a select command

                let selectTask = Task { 

                    try await session.select(mailbox: "INBOX") 

                }

                

                // Wait briefly to allow send to occur

                try await Task.sleep(nanoseconds: 10_000_000)

                

                // Simulate connection drop by finishing the stream

                await transport.stop()

                

                do {

                    _ = try await selectTask.value

                    #expect(Bool(false), "Should have thrown an error")

                } catch let error as SessionError {

                    if case .connectionClosed(let message) = error {

                        #expect(message == "Connection closed by server.")

                    } else {

                        #expect(Bool(false), "Unexpected error type: \(error)")

                    }

                } catch {

                    #expect(Bool(false), "Unexpected error type: \(error)")

                }

            }

        

    

            @Test("Async SMTP session handles unexpected connection drop during command")

        

    

            func asyncSmtpConnectionDrop() async throws {

        

    

                let transport = AsyncStreamTransport()

        

    

                let session = AsyncSmtpSession(transport: transport, timeoutMilliseconds: 500)

        

    

        

        

    

                // Connect

        

    

                let connectTask = Task { try await session.connect() }

        

    

                await transport.yieldIncoming(Array("220 smtp.example.com ESMTP\r\n".utf8))

        

    

                _ = try await connectTask.value

        

    

        

        

    

                // Start a command

        

    

                let noopTask = Task { 

        

    

                    try await session.noop() 

        

    

                }

        

    

                

        

    

                try await Task.sleep(nanoseconds: 10_000_000)

        

    

                

        

    

                // Simulate connection drop

        

    

                await transport.stop()

        

    

                

        

    

                do {

        

    

                    _ = try await noopTask.value

        

    

                    #expect(Bool(false), "Should have thrown an error")

        

    

                } catch let error as SessionError {

        

    

                    if case .connectionClosed(let message) = error {

        

    

                        #expect(message == "Connection closed by server.")

        

    

                    } else {

        

    

                        #expect(Bool(false), "Unexpected error type: \(error)")

        

    

                    }

        

    

                } catch {

        

    

                    #expect(Bool(false), "Unexpected error type: \(error)")

        

    

                }

        

    

            }

    
}
