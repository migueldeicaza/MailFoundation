//
// Envelope+Headers.swift
//
// Apply header values to Envelope fields.
//

import Foundation
import MimeFoundation

public extension Envelope {
    convenience init(headers: HeaderList) {
        self.init()
        apply(headers: headers)
    }
    func apply(headers: [Header]) {
        for header in headers {
            apply(header: header)
        }
    }

    func apply(headers: HeaderList) {
        for header in headers {
            apply(header: header)
        }
    }

    func apply(header: Header) {
        apply(header: header.field, value: header.value)
    }

    func apply(headers: [String: String]) {
        for (name, value) in headers {
            apply(header: name, value: value)
        }
    }

    func apply(header name: String, value: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "subject":
            subject = SubjectDecoder.decode(value)
        case "date":
            date = DateUtils.tryParse(value)
        case "from":
            replaceAddressList(from, with: try? AddressParser.parseList(value))
        case "sender":
            replaceAddressList(sender, with: try? AddressParser.parseList(value))
        case "reply-to":
            replaceAddressList(replyTo, with: try? AddressParser.parseList(value))
        case "to":
            replaceAddressList(to, with: try? AddressParser.parseList(value))
        case "cc":
            replaceAddressList(cc, with: try? AddressParser.parseList(value))
        case "bcc":
            replaceAddressList(bcc, with: try? AddressParser.parseList(value))
        case "message-id":
            messageId = MessageIdList.parseMessageId(value) ?? value
        case "in-reply-to":
            inReplyTo = MessageIdList.parseAll(value).first ?? value
        case "references":
            if inReplyTo == nil {
                inReplyTo = MessageIdList.parseAll(value).last ?? value
            }
        case "list-id":
            listId = normalizeListId(value)
        case "list-archive":
            listArchive = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-help":
            listHelp = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-owner":
            listOwner = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-post":
            listPost = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-subscribe":
            listSubscribe = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-unsubscribe":
            listUnsubscribe = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "list-unsubscribe-post":
            listUnsubscribePost = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "arc-seal":
            arcSeals.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "arc-message-signature":
            arcMessageSignatures.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "arc-authentication-results":
            arcAuthenticationResults.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "dkim-signature":
            dkimSignatures.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "domainkey-signature":
            domainKeySignatures.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "authentication-results":
            authenticationResults.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case "received-spf":
            receivedSpf.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            break
        }
    }

    private func normalizeListId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "<"),
              let end = trimmed[start...].firstIndex(of: ">"),
              end > start else {
            return trimmed
        }
        let innerStart = trimmed.index(after: start)
        let inner = trimmed[innerStart..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? trimmed : String(inner)
    }

    private func replaceAddressList(_ list: InternetAddressList, with newList: InternetAddressList?) {
        guard let newList else { return }
        list.clear()
        list.addRange(Array(newList))
    }
}
