import Testing
import SwiftMimeKit
@testable import MailFoundation

@Test("Envelope list-id normalization")
func envelopeListIdNormalization() {
    let headers = HeaderList()
    headers.add(Header(field: "List-Id", value: "Example List <list.example.com>"))
    let envelope = Envelope(headers: headers)
    #expect(envelope.listId == "list.example.com")
}

@Test("Envelope captures list + auth headers")
func envelopeHeaderExpansions() {
    let headers = HeaderList()
    headers.add(Header(field: "List-Owner", value: "<mailto:owner@example.com>"))
    headers.add(Header(field: "List-Unsubscribe-Post", value: "List-Unsubscribe=One-Click"))
    headers.add(Header(field: "ARC-Authentication-Results", value: "i=1; mx.example.com; spf=pass"))
    headers.add(Header(field: "ARC-Seal", value: "i=1; a=rsa-sha256; d=example.com; s=arc;"))
    headers.add(Header(field: "ARC-Message-Signature", value: "i=1; a=rsa-sha256; d=example.com; s=arc;"))
    headers.add(Header(field: "DomainKey-Signature", value: "a=rsa-sha1; d=example.com; s=mail;"))
    let envelope = Envelope(headers: headers)
    #expect(envelope.listOwner == "<mailto:owner@example.com>")
    #expect(envelope.listUnsubscribePost == "List-Unsubscribe=One-Click")
    #expect(envelope.arcAuthenticationResults.first == "i=1; mx.example.com; spf=pass")
    #expect(envelope.arcSeals.count == 1)
    #expect(envelope.arcMessageSignatures.count == 1)
    #expect(envelope.domainKeySignatures.count == 1)
}
