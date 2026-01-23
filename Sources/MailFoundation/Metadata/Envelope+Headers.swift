//
// Envelope+Headers.swift
//
// Apply header values to Envelope fields.
//

import Foundation
import SwiftMimeKit

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
            replaceAddressList(from, with: AddressParser.tryParseList(value))
        case "sender":
            replaceAddressList(sender, with: AddressParser.tryParseList(value))
        case "reply-to":
            replaceAddressList(replyTo, with: AddressParser.tryParseList(value))
        case "to":
            replaceAddressList(to, with: AddressParser.tryParseList(value))
        case "cc":
            replaceAddressList(cc, with: AddressParser.tryParseList(value))
        case "bcc":
            replaceAddressList(bcc, with: AddressParser.tryParseList(value))
        case "message-id":
            messageId = MessageIdList.parseAll(value).first ?? value
        case "in-reply-to":
            inReplyTo = MessageIdList.parseAll(value).first ?? value
        case "references":
            if inReplyTo == nil {
                inReplyTo = MessageIdList.parseAll(value).last ?? value
            }
        default:
            break
        }
    }

    private func replaceAddressList(_ list: InternetAddressList, with newList: InternetAddressList?) {
        guard let newList else { return }
        list.clear()
        list.addRange(Array(newList))
    }
}
