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
