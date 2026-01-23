//
// MailFolderBase.swift
//
// Shared folder base types.
//

public enum FolderAccess: Sendable, Equatable {
    case readOnly
    case readWrite
}

open class MailFolderBase: MailFolder {
    public let fullName: String
    public let name: String
    public let delimiter: String?

    public private(set) var access: FolderAccess?

    public var isOpen: Bool {
        access != nil
    }

    public init(fullName: String, delimiter: String? = nil) {
        self.fullName = fullName
        self.delimiter = delimiter
        self.name = MailFolderBase.computeName(fullName, delimiter: delimiter)
    }

    public func updateOpenState(_ access: FolderAccess?) {
        self.access = access
    }

    public static func computeName(_ fullName: String, delimiter: String?) -> String {
        guard let delimiter, let delimiterChar = delimiter.first else { return fullName }
        return fullName.split(separator: delimiterChar).last.map(String.init) ?? fullName
    }
}

@available(macOS 10.15, iOS 13.0, *)
public actor AsyncMailFolderBase: AsyncMailFolder {
    public nonisolated let fullName: String
    public nonisolated let name: String
    public nonisolated let delimiter: String?

    private var access: FolderAccess?

    public init(fullName: String, delimiter: String? = nil) {
        self.fullName = fullName
        self.delimiter = delimiter
        self.name = MailFolderBase.computeName(fullName, delimiter: delimiter)
    }

    public var isOpen: Bool {
        access != nil
    }

    public func updateOpenState(_ access: FolderAccess?) {
        self.access = access
    }
}
