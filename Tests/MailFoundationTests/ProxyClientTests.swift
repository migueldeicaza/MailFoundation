import Testing
@testable import MailFoundation

@Test("HTTP CONNECT proxy client sends CONNECT and accepts 200")
func httpProxyClientConnect() throws {
    let transport = TestTransport(incoming: [
        Array("HTTP/1.1 200 Connection established\r\n\r\n".utf8)
    ])
    let client = HttpProxyClient(
        transport: transport,
        username: "user",
        password: "pass"
    )

    try client.connect(to: "imap.example.com", port: 993)

    let sent = String(decoding: transport.written.first ?? [], as: UTF8.self)
    #expect(sent.contains("CONNECT imap.example.com:993 HTTP/1.1\r\n"))
    #expect(sent.contains("Host: imap.example.com:993\r\n"))
    #expect(sent.contains("Proxy-Authorization: Basic "))
}

@Test("SOCKS5 proxy client sends greeting and connect request")
func socks5ProxyClientConnect() throws {
    let transport = TestTransport(incoming: [
        [0x05, 0x00],
        [0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]
    ])
    let client = Socks5ProxyClient(transport: transport)

    try client.connect(to: "127.0.0.1", port: 8080)

    #expect(transport.written.count == 2)
    #expect(transport.written[0] == [0x05, 0x01, 0x00])
    #expect(transport.written[1] == [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90])
}

@Test("SOCKS4 proxy client uses SOCKS4a for domain")
func socks4ProxyClientDomainConnect() throws {
    let transport = TestTransport(incoming: [
        [0x00, 0x5A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    ])
    let client = Socks4ProxyClient(transport: transport, userId: "user", useSocks4a: true)

    try client.connect(to: "example.com", port: 110)

    let sent = transport.written.first ?? []
    #expect(sent.count > 9)
    #expect(Array(sent.prefix(4)) == [0x04, 0x01, 0x00, 0x6E])
    #expect(Array(sent[4..<8]) == [0x00, 0x00, 0x00, 0x01])
    #expect(sent.contains(0x00))
}
