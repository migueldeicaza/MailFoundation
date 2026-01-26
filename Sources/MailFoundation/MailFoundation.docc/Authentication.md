# Authentication

Configure authentication for IMAP, SMTP, and POP3 connections.

## Overview

MailFoundation supports multiple authentication mechanisms to work with different mail servers. This guide covers username/password authentication, OAuth2, and SASL mechanisms.

## Basic Username/Password Authentication

The simplest authentication method uses a username and password:

```swift
// IMAP
let imapStore = try ImapMailStore.make(host: "imap.example.com", port: 993, useTls: true)
try imapStore.connect()
try imapStore.authenticate(username: "user@example.com", password: "password")

// SMTP
let smtpTransport = try SmtpTransport.make(host: "smtp.example.com", port: 587)
try smtpTransport.connect()
try smtpTransport.authenticate(username: "user@example.com", password: "password")

// POP3
let pop3Store = try Pop3MailStore.make(host: "pop.example.com", port: 995, useTls: true)
try pop3Store.connect()
try pop3Store.authenticate(username: "user@example.com", password: "password")
```

## OAuth2 Authentication

For Gmail, Microsoft 365, and other OAuth2 providers, use XOAUTH2:

```swift
// Obtain an access token from your OAuth2 provider
let accessToken = "ya29.a0AfH6SMB..."

// IMAP with OAuth2
let imapStore = try ImapMailStore.make(host: "imap.gmail.com", port: 993, useTls: true)
try imapStore.connect()
try imapStore.authenticateOAuth2(username: "user@gmail.com", accessToken: accessToken)

// SMTP with OAuth2
let smtpTransport = try SmtpTransport.make(host: "smtp.gmail.com", port: 587)
try smtpTransport.connect()
try smtpTransport.authenticateOAuth2(username: "user@gmail.com", accessToken: accessToken)
```

### Gmail OAuth2 Setup

To use OAuth2 with Gmail:

1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the Gmail API
3. Create OAuth2 credentials (Client ID and Secret)
4. Request the `https://mail.google.com/` scope
5. Exchange the authorization code for access and refresh tokens

### Microsoft 365 OAuth2 Setup

For Microsoft 365 (Exchange Online):

1. Register an application in [Azure Portal](https://portal.azure.com/)
2. Configure API permissions for IMAP/SMTP
3. Use scopes like `https://outlook.office365.com/IMAP.AccessAsUser.All`
4. Follow the OAuth2 authorization code flow

## SASL Mechanisms

MailFoundation supports several SASL authentication mechanisms:

| Mechanism | Security | Description |
|-----------|----------|-------------|
| PLAIN | Low | Sends credentials in base64 (use with TLS) |
| LOGIN | Low | Legacy two-step authentication |
| CRAM-MD5 | Medium | Challenge-response with MD5 |
| XOAUTH2 | High | OAuth2 bearer token |

The library automatically selects the most secure mechanism available:

```swift
// The session will negotiate the best available mechanism
try session.authenticate(username: "user", password: "pass")
```

To use a specific mechanism:

```swift
// Force CRAM-MD5
try session.authenticate(
    username: "user",
    password: "pass",
    mechanism: .cramMd5
)
```

## POP3 APOP Authentication

POP3 servers may support APOP (Authenticated Post Office Protocol), which avoids sending passwords in cleartext:

```swift
let session = Pop3Session(transport: transport)
try session.connect()

// Check if APOP is available (server sends a timestamp in greeting)
if session.supportsApop {
    try session.authenticateApop(username: "user", password: "pass")
} else {
    try session.authenticate(username: "user", password: "pass")
}
```

## TLS and Security

Always use TLS to protect credentials in transit:

```swift
// Implicit TLS (port 993 for IMAP, 995 for POP3, 465 for SMTP)
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true
)

// STARTTLS (upgrade connection after connecting)
let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 143,
    useTls: false  // Connect plain, then upgrade
)
try store.connect()
try store.startTls()  // Upgrade to TLS
try store.authenticate(username: "user", password: "pass")
```

### TLS Configuration

Customize TLS settings for specific requirements:

```swift
let tlsConfig = TlsConfiguration(
    minProtocolVersion: .tlsv12,
    maxProtocolVersion: .tlsv13,
    validateCertificates: true
)

let store = try ImapMailStore.make(
    host: "imap.example.com",
    port: 993,
    useTls: true,
    tlsConfiguration: tlsConfig
)
```

### Certificate Validation

For self-signed certificates or custom CAs:

```swift
let tlsConfig = TlsConfiguration(
    validateCertificates: false  // Disable validation (not recommended for production)
)

// Or provide a custom validation callback
let tlsConfig = TlsConfiguration(
    certificateValidator: { context in
        // Custom validation logic
        return true  // Accept certificate
    }
)
```

## Server Capabilities

Check what authentication mechanisms a server supports:

```swift
// IMAP
let session = ImapSession(transport: transport)
try session.connect()
let capabilities = session.capabilities

if capabilities.contains(.authPlain) {
    print("Server supports PLAIN authentication")
}
if capabilities.contains(.authXOAuth2) {
    print("Server supports OAuth2")
}

// SMTP
let smtpSession = SmtpSession(transport: transport)
try smtpSession.connect()
try smtpSession.ehlo(domain: "client.example.com")

if smtpSession.capabilities.contains(.authPlain) {
    print("SMTP server supports PLAIN")
}
```

## Error Handling

Handle authentication failures gracefully:

```swift
do {
    try store.authenticate(username: "user", password: "wrong")
} catch let error as SessionError {
    switch error {
    case .authenticationFailed(let message):
        print("Authentication failed: \(message)")
    case .notConnected:
        print("Not connected to server")
    default:
        print("Session error: \(error)")
    }
}
```

## Best Practices

1. **Always use TLS** - Never send credentials over unencrypted connections
2. **Prefer OAuth2** - When available, OAuth2 is more secure than passwords
3. **Store credentials securely** - Use Keychain on Apple platforms
4. **Handle token refresh** - OAuth2 tokens expire; implement refresh logic
5. **Check capabilities first** - Verify the server supports your auth method
6. **Use app-specific passwords** - For accounts with 2FA enabled
