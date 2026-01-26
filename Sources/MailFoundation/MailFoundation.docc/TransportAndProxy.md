# Transport and Proxy Configuration

Configure network transports, TLS settings, and proxy connections.

## Overview

MailFoundation's transport layer handles the low-level network communication for all protocols. This guide covers transport configuration, TLS/SSL settings, proxy support, and connection pooling.

## Transport Architecture

The transport layer provides a consistent abstraction for network I/O:

```
┌─────────────────────────────────────────────────────────┐
│                   Protocol Session                       │
│              (IMAP, SMTP, POP3)                          │
├─────────────────────────────────────────────────────────┤
│                    Transport                             │
│         (read, write, TLS upgrade)                       │
├─────────────────────────────────────────────────────────┤
│                  Proxy Client                            │
│        (HTTP CONNECT, SOCKS4/5)                          │
├─────────────────────────────────────────────────────────┤
│                 Socket/Stream                            │
│         (TCP connection)                                 │
└─────────────────────────────────────────────────────────┘
```

## Creating Transports

### Synchronous Transport

```swift
import MailFoundation

// Basic TCP transport
let transport = try TransportFactory.make(
    host: "mail.example.com",
    port: 993
)

// With explicit backend selection
let transport = try TransportFactory.make(
    host: "mail.example.com",
    port: 993,
    backend: .socket  // or .tcp
)
```

### Asynchronous Transport

```swift
let transport = try await AsyncTransportFactory.make(
    host: "mail.example.com",
    port: 993,
    backend: .network  // or .socket
)
```

### Transport Backends

| Backend | Description | Platform |
|---------|-------------|----------|
| `.tcp` | Foundation streams | All |
| `.socket` | POSIX sockets + OpenSSL | macOS, Linux |
| `.network` | Network.framework | Apple platforms |

## TLS Configuration

### Basic TLS

```swift
// Implicit TLS (connection starts encrypted)
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true
)

// STARTTLS (upgrade after connecting)
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 143,
    useTls: false
)
try store.connect()
try store.startTls()  // Upgrade to TLS
```

### TLS Configuration Options

```swift
let tlsConfig = TlsConfiguration(
    // Protocol versions
    minProtocolVersion: .tlsv12,
    maxProtocolVersion: .tlsv13,

    // Certificate validation
    validateCertificates: true,

    // Client certificate (for mutual TLS)
    clientCertificate: certificateData,
    clientPrivateKey: privateKeyData
)

let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    tlsConfiguration: tlsConfig
)
```

### Custom Certificate Validation

```swift
let tlsConfig = TlsConfiguration(
    certificateValidator: { context in
        // context.host - server hostname
        // context.port - server port
        // context.trust - SecTrust object (Apple) or X509 chain (OpenSSL)

        // Custom validation logic
        let validHosts = ["mail.example.com", "backup.example.com"]
        guard validHosts.contains(context.host) else {
            return false
        }

        // Accept the certificate
        return true
    }
)
```

### Disabling Certificate Validation

> Warning: Only disable validation for testing. Never in production.

```swift
let tlsConfig = TlsConfiguration(
    validateCertificates: false
)
```

## Proxy Support

MailFoundation supports several proxy types for connecting through firewalls.

### HTTP CONNECT Proxy

```swift
let proxy = ProxySettings(
    type: .httpConnect,
    host: "proxy.example.com",
    port: 8080
)

let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    proxy: proxy
)
```

### HTTP CONNECT with Authentication

```swift
let proxy = ProxySettings(
    type: .httpConnect,
    host: "proxy.example.com",
    port: 8080,
    username: "proxyuser",
    password: "proxypass"
)
```

### SOCKS4 Proxy

```swift
let proxy = ProxySettings(
    type: .socks4,
    host: "proxy.example.com",
    port: 1080
)
```

### SOCKS4a Proxy

SOCKS4a supports hostname resolution by the proxy:

```swift
let proxy = ProxySettings(
    type: .socks4a,
    host: "proxy.example.com",
    port: 1080
)
```

### SOCKS5 Proxy

```swift
let proxy = ProxySettings(
    type: .socks5,
    host: "proxy.example.com",
    port: 1080,
    username: "user",      // Optional
    password: "password"   // Optional
)
```

### Proxy with All Protocols

```swift
// IMAP through proxy
let imapStore = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    proxy: proxy
)

// SMTP through proxy
let smtpTransport = try SmtpTransport.make(
    host: "smtp.example.com",
    port: 587,
    proxy: proxy
)

// POP3 through proxy
let pop3Store = try Pop3MailStore.make(
    host: "pop.example.com",
    port: 995,
    useTls: true,
    proxy: proxy
)
```

### Async Proxy Support

```swift
let proxy = ProxySettings(
    type: .socks5,
    host: "proxy.example.com",
    port: 1080
)

let store = try await AsyncImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    proxy: proxy
)
```

## Connection Pooling

For applications that need multiple connections, use ``ConnectionPool``:

```swift
let pool = ConnectionPool<ImapSession>(
    maxConnections: 5,
    factory: {
        let transport = try TransportFactory.make(host: "imap.example.com", port: 993)
        let session = ImapSession(transport: transport)
        try session.connect()
        try session.login(username: "user", password: "pass")
        return session
    },
    validator: { session in
        session.isConnected
    }
)

// Borrow a connection
let session = try await pool.acquire()

// Use the session
let messages = try session.search(query: .unseen)

// Return to pool
await pool.release(session)
```

### Pool Configuration

```swift
let pool = ConnectionPool<ImapSession>(
    maxConnections: 10,
    maxIdleTime: 300,  // 5 minutes
    factory: factory,
    validator: validator
)
```

## Timeouts

### Service Timeouts

Configure timeouts for operations:

```swift
let timeout = ServiceTimeout(
    connect: 30,     // 30 seconds to connect
    command: 60,     // 60 seconds per command
    idle: 1800       // 30 minutes for IDLE
)

let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    timeout: timeout
)
```

### Default Timeouts

| Operation | Default |
|-----------|---------|
| Connect | 30 seconds |
| Command | 120 seconds |
| IDLE | 29 minutes |

## Retry Policies

Handle transient failures automatically:

```swift
let policy = RetryPolicy(
    maxAttempts: 3,
    initialDelay: 1.0,
    maxDelay: 30.0,
    multiplier: 2.0
)

// Retry a failing operation
let result = try await withRetry(policy: policy) {
    try await store.connect()
}
```

## Protocol Logging

Debug network issues with protocol logging:

```swift
// Console logger
let logger = ConsoleProtocolLogger()

let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    protocolLogger: logger
)

// Credentials are automatically masked
// C: A001 LOGIN user@example.com ********
// S: A001 OK LOGIN completed
```

### Custom Logger

```swift
class MyLogger: ProtocolLogger {
    func logConnect(host: String, port: Int) {
        print("Connecting to \(host):\(port)")
    }

    func logSend(_ data: Data, secrets: [AuthenticationSecret]) {
        let text = String(data: data, encoding: .utf8) ?? ""
        // Mask secrets before logging
        print("C: \(mask(text, secrets: secrets))")
    }

    func logReceive(_ data: Data) {
        let text = String(data: data, encoding: .utf8) ?? ""
        print("S: \(text)")
    }

    func logDisconnect() {
        print("Disconnected")
    }
}
```

## Low-Level Transport Access

For advanced use cases, access the transport directly:

```swift
// Create raw transport
let transport = try TransportFactory.make(host: "example.com", port: 12345)

// Open connection
try transport.open()

// Write data
try transport.write(Data("Hello\r\n".utf8))

// Read response
let response = try transport.readLine()

// Upgrade to TLS
if let tlsTransport = transport as? StartTlsTransport {
    try tlsTransport.startTls()
}

// Close
transport.close()
```

## Error Handling

### Transport Errors

```swift
do {
    try transport.open()
} catch let error as TransportError {
    switch error {
    case .connectionFailed(let underlying):
        print("Connection failed: \(underlying)")
    case .tlsHandshakeFailed(let underlying):
        print("TLS handshake failed: \(underlying)")
    case .timeout:
        print("Operation timed out")
    case .disconnected:
        print("Connection was closed")
    }
}
```

### Proxy Errors

```swift
do {
    let transport = try TransportFactory.make(
        host: "imap.example.com",
        port: 993,
        proxy: proxy
    )
} catch let error as ProxyError {
    switch error {
    case .connectionFailed:
        print("Could not connect to proxy")
    case .authenticationFailed:
        print("Proxy authentication failed")
    case .hostUnreachable:
        print("Target host unreachable through proxy")
    case .commandRejected(let code, let message):
        print("Proxy rejected: \(code) \(message)")
    }
}
```

## Platform Considerations

### macOS and iOS

- Use `.network` backend for best integration with system settings
- Network.framework handles system proxy configuration automatically
- Supports App Transport Security (ATS) requirements

### Linux

- Use `.socket` backend with OpenSSL for TLS
- Requires OpenSSL to be installed
- Proxy settings must be configured explicitly

### Cross-Platform

- Use `.tcp` backend for maximum compatibility
- Works on all platforms with Foundation
- May not support all TLS features
