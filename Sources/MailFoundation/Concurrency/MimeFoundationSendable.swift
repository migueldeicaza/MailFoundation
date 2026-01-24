//
// MimeFoundationSendable.swift
//
// Concurrency annotations for MimeFoundation reference types.
//

import MimeFoundation

extension MimeMessage: @unchecked @retroactive Sendable {}
extension MailboxAddress: @unchecked @retroactive Sendable {}
extension InternetAddressList: @unchecked @retroactive Sendable {}
extension HeaderList: @unchecked @retroactive Sendable {}
