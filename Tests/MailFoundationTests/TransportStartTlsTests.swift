import Testing
@testable import MailFoundation

#if !os(iOS)
#if canImport(Security)
@available(macOS 10.15, iOS 13.0, *)
@Test("Socket transport async STARTTLS support")
func socketTransportStartTlsSupport() throws {
    let transport = try AsyncTransportFactory.make(host: "localhost", port: 1, backend: .socket)
    #expect(transport is AsyncStartTlsTransport)
}
#endif
#endif
