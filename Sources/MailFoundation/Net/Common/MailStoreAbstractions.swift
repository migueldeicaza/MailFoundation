//
// MailStoreAbstractions.swift
//
// Mail store and folder protocols.
//

public protocol MailFolder: AnyObject {
    var fullName: String { get }
    var name: String { get }
}

public protocol AsyncMailFolder {
    var fullName: String { get }
    var name: String { get }
}

public protocol MailStore: MailService {
    associatedtype FolderType: MailFolder

    func getFolder(_ path: String) throws -> FolderType
    func getFolders(reference: String, pattern: String, subscribedOnly: Bool) throws -> [FolderType]
}

@available(macOS 10.15, iOS 13.0, *)
public protocol AsyncMailStore: AsyncMailService {
    associatedtype FolderType: AsyncMailFolder

    func getFolder(_ path: String) async throws -> FolderType
    func getFolders(reference: String, pattern: String, subscribedOnly: Bool) async throws -> [FolderType]
}
