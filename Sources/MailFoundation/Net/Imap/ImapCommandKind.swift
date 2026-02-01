//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

//
// ImapCommandKind.swift
//
// IMAP command definitions.
//

/// Quotes a string for use in IMAP commands.
///
/// Always wraps the string in double quotes and escapes backslashes and quotes.
private func imapQuote(_ value: String) -> String {
    var result = "\""
    for ch in value {
        if ch == "\\" || ch == "\"" {
            result.append("\\")
        }
        result.append(ch)
    }
    result.append("\"")
    return result
}

/// Returns true if the scalar is a valid IMAP atom character.
///
/// Mirrors MailKit's atom character rules.
private func imapIsAtomScalar(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value >= 0x80 || scalar.value <= 0x1F || scalar.value == 0x7F {
        return false
    }
    switch scalar.value {
    case 0x28, 0x29, 0x7B, 0x20, 0x25, 0x2A, 0x5C, 0x22, 0x5D:
        return false
    default:
        return true
    }
}

/// Formats an IMAP astring, quoting when needed.
///
/// This mirrors MailKit's atom/quoted selection (without literal support).
private func imapAString(_ value: String) -> String {
    guard !value.isEmpty else {
        return "\"\""
    }
    for scalar in value.unicodeScalars {
        if !imapIsAtomScalar(scalar) {
            return imapQuote(value)
        }
    }
    return value
}

public enum ImapCommandKind: Sendable {
    case capability
    case noop
    case login(String, String)
    case authenticate(String, initialResponse: String?)
    case select(String)
    case examine(String)
    case logout
    case create(String)
    case delete(String)
    case rename(String, String)
    case subscribe(String)
    case unsubscribe(String)
    case list(String, String)
    case listExtended(String, String, returns: [ImapListReturnOption])
    case listSpecialUse(String, String)
    case listStatus(String, String, items: [String])
    case lsub(String, String)
    case xlist(String, String)
    case status(String, items: [String])
    case check
    case close
    case expunge
    case namespace
    case getQuota(String)
    case getQuotaRoot(String)
    case getAcl(String)
    case setAcl(String, identifier: String, rights: String)
    case listRights(String, identifier: String)
    case myRights(String)
    case getMetadata(String, options: ImapMetadataOptions?, entries: [String])
    case setMetadata(String, entries: [ImapMetadataEntry])
    case getAnnotation(String, entries: [String], attributes: [String])
    case setAnnotation(String, entry: String, attributes: [ImapAnnotationAttribute])
    case id(String)
    case fetch(String, String)
    case store(String, String)
    case copy(String, String)
    case move(String, String)
    case search(String)
    case sort(String)
    case uidFetch(String, String)
    case uidStore(String, String)
    case uidCopy(String, String)
    case uidMove(String, String)
    case uidSearch(String)
    case uidSort(String)
    case enable([String])
    case idle
    case idleDone
    case starttls
    case notify(String)
    case compress(String)

    public func command(tag: String) -> ImapCommand {
        switch self {
        case .capability:
            return ImapCommand(tag: tag, name: "CAPABILITY")
        case .noop:
            return ImapCommand(tag: tag, name: "NOOP")
        case let .login(user, password):
            return ImapCommand(tag: tag, name: "LOGIN", arguments: "\(user) \(password)")
        case let .authenticate(mechanism, initialResponse):
            if let response = initialResponse {
                return ImapCommand(tag: tag, name: "AUTHENTICATE", arguments: "\(mechanism) \(response)")
            }
            return ImapCommand(tag: tag, name: "AUTHENTICATE", arguments: mechanism)
        case let .select(mailbox):
            return ImapCommand(tag: tag, name: "SELECT", arguments: imapAString(mailbox))
        case let .examine(mailbox):
            return ImapCommand(tag: tag, name: "EXAMINE", arguments: imapAString(mailbox))
        case .logout:
            return ImapCommand(tag: tag, name: "LOGOUT")
        case let .create(mailbox):
            return ImapCommand(tag: tag, name: "CREATE", arguments: imapAString(mailbox))
        case let .delete(mailbox):
            return ImapCommand(tag: tag, name: "DELETE", arguments: imapAString(mailbox))
        case let .rename(from, to):
            return ImapCommand(tag: tag, name: "RENAME", arguments: "\(imapAString(from)) \(imapAString(to))")
        case let .subscribe(mailbox):
            return ImapCommand(tag: tag, name: "SUBSCRIBE", arguments: imapAString(mailbox))
        case let .unsubscribe(mailbox):
            return ImapCommand(tag: tag, name: "UNSUBSCRIBE", arguments: imapAString(mailbox))
        case let .list(reference, mailbox):
            return ImapCommand(tag: tag, name: "LIST", arguments: "\(imapAString(reference)) \(imapAString(mailbox))")
        case let .listExtended(reference, mailbox, returns):
            if returns.isEmpty {
                return ImapCommand(tag: tag, name: "LIST", arguments: "\(imapAString(reference)) \(imapAString(mailbox))")
            }
            let options = returns.map { $0.serialized }.joined(separator: " ")
            return ImapCommand(
                tag: tag,
                name: "LIST",
                arguments: "\(imapAString(reference)) \(imapAString(mailbox)) RETURN (\(options))"
            )
        case let .listSpecialUse(reference, mailbox):
            return ImapCommand(
                tag: tag,
                name: "LIST",
                arguments: "(SPECIAL-USE) \(imapAString(reference)) \(imapAString(mailbox))"
            )
        case let .listStatus(reference, mailbox, items):
            let itemList = items.joined(separator: " ")
            return ImapCommand(
                tag: tag,
                name: "LIST",
                arguments: "\(imapAString(reference)) \(imapAString(mailbox)) RETURN (STATUS (\(itemList)))"
            )
        case let .lsub(reference, mailbox):
            return ImapCommand(tag: tag, name: "LSUB", arguments: "\(imapAString(reference)) \(imapAString(mailbox))")
        case let .xlist(reference, mailbox):
            return ImapCommand(tag: tag, name: "XLIST", arguments: "\(imapAString(reference)) \(imapAString(mailbox))")
        case let .status(mailbox, items):
            let itemList = items.joined(separator: " ")
            return ImapCommand(tag: tag, name: "STATUS", arguments: "\(imapAString(mailbox)) (\(itemList))")
        case .check:
            return ImapCommand(tag: tag, name: "CHECK")
        case .close:
            return ImapCommand(tag: tag, name: "CLOSE")
        case .expunge:
            return ImapCommand(tag: tag, name: "EXPUNGE")
        case .namespace:
            return ImapCommand(tag: tag, name: "NAMESPACE")
        case let .getQuota(root):
            return ImapCommand(tag: tag, name: "GETQUOTA", arguments: imapAString(root))
        case let .getQuotaRoot(mailbox):
            return ImapCommand(tag: tag, name: "GETQUOTAROOT", arguments: imapAString(mailbox))
        case let .getAcl(mailbox):
            return ImapCommand(tag: tag, name: "GETACL", arguments: imapAString(mailbox))
        case let .setAcl(mailbox, identifier, rights):
            return ImapCommand(tag: tag, name: "SETACL", arguments: "\(imapAString(mailbox)) \(imapAString(identifier)) \(imapAString(rights))")
        case let .listRights(mailbox, identifier):
            return ImapCommand(tag: tag, name: "LISTRIGHTS", arguments: "\(imapAString(mailbox)) \(imapAString(identifier))")
        case let .myRights(mailbox):
            return ImapCommand(tag: tag, name: "MYRIGHTS", arguments: imapAString(mailbox))
        case let .getMetadata(mailbox, options, entries):
            let entryList = ImapMetadata.formatEntryList(entries)
            if let options = options?.arguments() {
                return ImapCommand(tag: tag, name: "GETMETADATA", arguments: "\(imapAString(mailbox)) \(options) \(entryList)")
            }
            return ImapCommand(tag: tag, name: "GETMETADATA", arguments: "\(imapAString(mailbox)) \(entryList)")
        case let .setMetadata(mailbox, entries):
            let entryList = ImapMetadata.formatEntryPairs(entries)
            return ImapCommand(tag: tag, name: "SETMETADATA", arguments: "\(imapAString(mailbox)) \(entryList)")
        case let .getAnnotation(mailbox, entries, attributes):
            let entryList = ImapAnnotation.formatEntryList(entries)
            let attributeList = ImapAnnotation.formatAttributeList(attributes)
            return ImapCommand(tag: tag, name: "GETANNOTATION", arguments: "\(imapAString(mailbox)) \(entryList) \(attributeList)")
        case let .setAnnotation(mailbox, entry, attributes):
            let attributeList = ImapAnnotation.formatAttributes(attributes)
            let entryName = ImapMetadata.atomOrQuoted(entry)
            return ImapCommand(tag: tag, name: "SETANNOTATION", arguments: "\(imapAString(mailbox)) \(entryName) \(attributeList)")
        case let .id(arguments):
            return ImapCommand(tag: tag, name: "ID", arguments: arguments)
        case let .fetch(set, items):
            return ImapCommand(tag: tag, name: "FETCH", arguments: "\(set) \(items)")
        case let .store(set, data):
            return ImapCommand(tag: tag, name: "STORE", arguments: "\(set) \(data)")
        case let .copy(set, mailbox):
            return ImapCommand(tag: tag, name: "COPY", arguments: "\(set) \(imapAString(mailbox))")
        case let .move(set, mailbox):
            return ImapCommand(tag: tag, name: "MOVE", arguments: "\(set) \(imapAString(mailbox))")
        case let .search(criteria):
            return ImapCommand(tag: tag, name: "SEARCH", arguments: criteria)
        case let .sort(criteria):
            return ImapCommand(tag: tag, name: "SORT", arguments: criteria)
        case let .uidFetch(set, items):
            return ImapCommand(tag: tag, name: "UID FETCH", arguments: "\(set) \(items)")
        case let .uidStore(set, data):
            return ImapCommand(tag: tag, name: "UID STORE", arguments: "\(set) \(data)")
        case let .uidCopy(set, mailbox):
            return ImapCommand(tag: tag, name: "UID COPY", arguments: "\(set) \(imapAString(mailbox))")
        case let .uidMove(set, mailbox):
            return ImapCommand(tag: tag, name: "UID MOVE", arguments: "\(set) \(imapAString(mailbox))")
        case let .uidSearch(criteria):
            return ImapCommand(tag: tag, name: "UID SEARCH", arguments: criteria)
        case let .uidSort(criteria):
            return ImapCommand(tag: tag, name: "UID SORT", arguments: criteria)
        case let .enable(capabilities):
            let list = capabilities.joined(separator: " ")
            return ImapCommand(tag: tag, name: "ENABLE", arguments: list)
        case .idle:
            return ImapCommand(tag: tag, name: "IDLE")
        case .idleDone:
            return ImapCommand(tag: "", name: "DONE")
        case .starttls:
            return ImapCommand(tag: tag, name: "STARTTLS")
        case let .notify(arguments):
            return ImapCommand(tag: tag, name: "NOTIFY", arguments: arguments)
        case let .compress(algorithm):
            return ImapCommand(tag: tag, name: "COMPRESS", arguments: algorithm)
        }
    }
}
