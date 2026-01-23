//
// ThreadingReferences.swift
//
// Helpers for combining References and In-Reply-To headers.
//

public struct ThreadingReferences: Sendable, Equatable, CustomStringConvertible {
    public let ids: [String]

    public init(_ ids: [String]) {
        self.ids = ids
    }

    public var description: String {
        ids.joined(separator: " ")
    }

    public static func merge(inReplyTo: String?, references: String?) -> ThreadingReferences? {
        var combined: [String] = []

        if let references {
            combined.append(contentsOf: MessageIdList.parseAll(references))
        }

        if let inReplyTo {
            let ids = MessageIdList.parseAll(inReplyTo)
            for id in ids where !combined.contains(id) {
                combined.append(id)
            }
        }

        guard !combined.isEmpty else { return nil }
        return ThreadingReferences(combined)
    }

    public static func merge(referencesHeader: ReferencesHeader?, inReplyToHeader: InReplyToHeader?) -> ThreadingReferences? {
        let references = referencesHeader?.description
        let inReplyTo = inReplyToHeader?.description
        return merge(inReplyTo: inReplyTo, references: references)
    }
}
