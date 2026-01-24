import Testing
@testable import MailFoundation

#if canImport(Network) && canImport(Security) && !os(iOS)
import Foundation
@preconcurrency import Security
import Darwin

@available(macOS 10.15, iOS 13.0, *)
@Test("Network transport STARTTLS integration success with validation disabled")
func networkTransportStartTlsSuccess() async throws {
    let identity = try await StartTlsIdentityProvider.identity()
    let server = try StartTlsStreamServer(identity: identity)
    server.start()
    defer { server.stop() }

    let transport = NetworkTransport(host: "127.0.0.1", port: server.port)
    let session = AsyncSmtpSession(transport: transport)

    let connectTask = Task { try await session.connect() }
    _ = try await connectTask.value

    let startTlsTask = Task { try await session.startTls(validateCertificate: false) }
    _ = try await startTlsTask.value

    let noopTask = Task { try await session.noop() }
    let response = try await noopTask.value
    #expect(response?.code == 250)
}

@available(macOS 10.15, iOS 13.0, *)
@Test("Network transport STARTTLS integration fails with validation enabled")
func networkTransportStartTlsValidationFailure() async throws {
    let identity = try await StartTlsIdentityProvider.identity()
    let server = try StartTlsStreamServer(identity: identity)
    server.start()
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

private enum StartTlsIntegrationError: Error {
    case identityImportFailed
    case socketFailed
    case streamPairFailed
}

@available(macOS 10.15, iOS 13.0, *)
private enum StartTlsIdentityProvider {
    @MainActor
    static func identity() throws -> SecIdentity {
        let base64 =
        "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"
        guard let data = Data(base64Encoded: base64) else {
            throw StartTlsIntegrationError.identityImportFailed
        }
        let options = [kSecImportExportPassphrase as String: "password"] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let identity = array.first?[kSecImportItemIdentity as String] else {
            throw StartTlsIntegrationError.identityImportFailed
        }
        let secIdentity = identity as! SecIdentity
        return secIdentity
    }
}

@available(macOS 10.15, iOS 13.0, *)
private final class StartTlsStreamServer: @unchecked Sendable {
    private let identity: SecIdentity
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?

    var port: UInt16 = 0

    init(identity: SecIdentity) throws {
        self.identity = identity
        try setupSocket()
    }

    func start() {
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread = thread
        thread.start()
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    private func setupSocket() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw StartTlsIntegrationError.socketFailed
        }

        var value: Int32 = 1
        _ = setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw StartTlsIntegrationError.socketFailed
        }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var boundAddr = sockaddr_in()
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listenFD, $0, &len)
            }
        }
        guard nameResult == 0 else {
            throw StartTlsIntegrationError.socketFailed
        }
        port = UInt16(bigEndian: boundAddr.sin_port)

        guard listen(listenFD, 1) == 0 else {
            throw StartTlsIntegrationError.socketFailed
        }
    }

    private func acceptLoop() {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenFD, $0, &len)
            }
        }
        guard clientFD >= 0 else { return }

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, clientFD, &readStream, &writeStream)
        guard let readStream, let writeStream else { return }

        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.open()
        output.open()

        writeLine("220 Ready", to: output)

        var tlsEnabled = false
        while let line = readLine(from: input) {
            let upper = line.uppercased()
            if upper.hasPrefix("STARTTLS") {
                writeLine("220 Go ahead", to: output)
                enableTls(input: input, output: output)
                tlsEnabled = true
                continue
            }
            if tlsEnabled, upper.hasPrefix("NOOP") {
                writeLine("250 OK", to: output)
                break
            }
        }

        input.close()
        output.close()
        close(clientFD)
    }

    private func enableTls(input: InputStream, output: OutputStream) {
        let settings: [String: Any] = [
            kCFStreamSSLIsServer as String: true,
            kCFStreamSSLCertificates as String: [identity]
        ]
        let key = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        _ = input.setProperty(settings, forKey: key)
        _ = output.setProperty(settings, forKey: key)
    }

    private func writeLine(_ line: String, to output: OutputStream) {
        let data = Array("\(line)\r\n".utf8)
        _ = data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return output.write(base, maxLength: data.count)
        }
    }

    private func readLine(from input: InputStream) -> String? {
        var buffer = [UInt8](repeating: 0, count: 1)
        var collected: [UInt8] = []
        while true {
            let count = input.read(&buffer, maxLength: 1)
            if count <= 0 {
                return nil
            }
            collected.append(buffer[0])
            if collected.count >= 2,
               collected[collected.count - 2] == 0x0D,
               collected[collected.count - 1] == 0x0A {
                collected.removeLast(2)
                break
            }
        }
        return String(decoding: collected, as: UTF8.self)
    }
}
#endif
