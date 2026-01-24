//
// SwiftMimeKitSendable.swift
//
// Concurrency annotations for SwiftMimeKit reference types.
//

import SwiftMimeKit

extension MimeMessage: @unchecked @retroactive Sendable {}
extension MailboxAddress: @unchecked @retroactive Sendable {}
extension InternetAddressList: @unchecked @retroactive Sendable {}
extension HeaderList: @unchecked @retroactive Sendable {}
