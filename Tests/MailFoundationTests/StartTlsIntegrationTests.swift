import Testing
@testable import MailFoundation

#if canImport(Network)
import Network
import Foundation

@available(macOS 10.15, iOS 13.0, *)
@Test("Network transport STARTTLS integration with connection drop")
func networkTransportStartTlsDrop() async throws {
    let server = try StartTlsDropServer()
    await server.start()
    defer { server.stop() }

    let transport = NetworkTransport(host: "127.0.0.1", port: server.port)
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: true) }
    _ = try await startTlsTask.value

    do {
        let response = try await session.noop()
        #expect(response == nil)
    } catch {
        #expect(Bool(true))
    }
}

@available(macOS 10.15, iOS 13.0, *)
private final class StartTlsDropServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mailfoundation.starttls.drop.server")
    private var connection: NWConnection?

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    init() throws {
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async {
        await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    continuation.resume()
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        connection?.cancel()
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            self?.sendGreeting(on: connection)
            self?.receive(on: connection)
        }
        connection.start(queue: queue)
    }

    private func sendGreeting(on connection: NWConnection) {
        let greeting = Array("220 Ready\r\n".utf8)
        connection.send(content: greeting, completion: .contentProcessed { _ in })
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, _ in
            if let data, let text = String(data: data, encoding: .utf8), text.contains("STARTTLS") {
                let response = Array("220 Go ahead\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            self?.receive(on: connection)
        }
    }
}
#endif
