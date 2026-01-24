//
// ImapSort.swift
//
// IMAP SORT command helpers.
//

public enum ImapSortError: Error, Sendable, Equatable {
    case emptyOrderBy
    case missingAnnotation
    case sortNotSupported
    case sortDisplayNotSupported
    case annotationNotSupported
    case unsupportedOrderByType(OrderByType)
}

public enum ImapSort {
    public static func validateCapabilities(orderBy: [OrderBy], capabilities: ImapCapabilities?) throws {
        guard let capabilities else { return }
        guard capabilities.supports("SORT") else { throw ImapSortError.sortNotSupported }

        if orderBy.contains(where: { $0.type == .displayFrom || $0.type == .displayTo }) {
            if !(capabilities.supports("SORT=DISPLAY") || capabilities.supports("SORTDISPLAY")) {
                throw ImapSortError.sortDisplayNotSupported
            }
        }

        if orderBy.contains(where: { $0.type == .annotation }) {
            if !(capabilities.supports("ANNOTATE") || capabilities.supports("ANNOTATION")) {
                throw ImapSortError.annotationNotSupported
            }
        }
    }

    public static func buildArguments(
        orderBy: [OrderBy],
        query: SearchQuery,
        charset: String = "UTF-8"
    ) throws -> String {
        let order = try buildOrderBy(orderBy)
        return "\(order) \(charset) \(query.serialize())"
    }

    public static func buildArguments(
        orderBy: [OrderBy],
        criteria: String,
        charset: String = "UTF-8"
    ) throws -> String {
        let order = try buildOrderBy(orderBy)
        return "\(order) \(charset) \(criteria)"
    }

    public static func buildOrderBy(_ orderBy: [OrderBy]) throws -> String {
        guard !orderBy.isEmpty else { throw ImapSortError.emptyOrderBy }
        var tokens: [String] = []

        for rule in orderBy {
            var parts: [String] = []
            if rule.order == .descending {
                parts.append("REVERSE")
            }

            switch rule.type {
            case .annotation:
                guard let annotation = rule.annotation else { throw ImapSortError.missingAnnotation }
                parts.append("ANNOTATION")
                parts.append(annotation.entry)
                parts.append(annotation.attribute)
            case .arrival:
                parts.append("ARRIVAL")
            case .cc:
                parts.append("CC")
            case .date:
                parts.append("DATE")
            case .displayFrom:
                parts.append("DISPLAYFROM")
            case .displayTo:
                parts.append("DISPLAYTO")
            case .from:
                parts.append("FROM")
            case .size:
                parts.append("SIZE")
            case .subject:
                parts.append("SUBJECT")
            case .to:
                parts.append("TO")
            case .modSeq:
                throw ImapSortError.unsupportedOrderByType(.modSeq)
            }

            tokens.append(parts.joined(separator: " "))
        }

        return "(\(tokens.joined(separator: " ")))"
    }
}
