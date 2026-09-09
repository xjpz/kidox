import Foundation

enum LaunchItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case application
    case folder
    case file
    case url

    var id: String { rawValue }
}

struct LocalizedApplicationName: Hashable, Codable, Sendable {
    let localeIdentifier: String
    let name: String
}

struct LaunchItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var kind: LaunchItemKind
    var displayName: String
    var subtitle: String
    var url: URL
    var bundleIdentifier: String?
    var bundleName: String?
    var localizedDisplayNames: [String]?
    var localizedSearchNames: [LocalizedApplicationName]?
    var applicationCategory: String?
    var version: String?
    var customDisplayName: String?
    var sourcePath: String
    var isHidden: Bool
    var sortIndex: Int
    var addedAt: Date
    var lastOpenedAt: Date?
    var openCount: Int
    var parentID: UUID?

    init(
        id: UUID = UUID(),
        kind: LaunchItemKind,
        displayName: String,
        subtitle: String,
        url: URL,
        bundleIdentifier: String? = nil,
        bundleName: String? = nil,
        localizedDisplayNames: [String]? = nil,
        localizedSearchNames: [LocalizedApplicationName]? = nil,
        applicationCategory: String? = nil,
        version: String? = nil,
        customDisplayName: String? = nil,
        sourcePath: String,
        isHidden: Bool = false,
        sortIndex: Int = 0,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        openCount: Int = 0,
        parentID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.subtitle = subtitle
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.bundleName = bundleName
        self.localizedDisplayNames = localizedDisplayNames
        self.localizedSearchNames = localizedSearchNames
        self.applicationCategory = applicationCategory
        self.version = version
        self.customDisplayName = customDisplayName
        self.sourcePath = sourcePath
        self.isHidden = isHidden
        self.sortIndex = sortIndex
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.openCount = openCount
        self.parentID = parentID
    }

    var effectiveDisplayName: String {
        customDisplayName ?? displayName
    }

}

struct LaunchItemSearchMatch: Comparable, Hashable {
    let score: Int

    static func < (lhs: LaunchItemSearchMatch, rhs: LaunchItemSearchMatch) -> Bool {
        lhs.score < rhs.score
    }
}

struct LaunchItemSearchQuery: Hashable {
    let normalized: String
    let tokens: [String]

    init?(_ value: String) {
        let normalized = value.kidoXSearchNormalized
        let tokens = normalized.kidoXSearchTokens
        guard !tokens.isEmpty else { return nil }

        self.normalized = normalized
        self.tokens = tokens
    }
}

extension LaunchItem {
    // Convenience for isolated callers. The live search path uses the store's cached entries.
    func searchMatch(for query: LaunchItemSearchQuery) -> LaunchItemSearchMatch? {
        ApplicationSearchIndex.Entry(.init(self, language: Locale.preferredLanguages.first ?? "en")).match(query)
    }
}

extension String {
    var kidoXSearchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .localizedLowercase
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var kidoXSearchTokens: [String] {
        split { character in
            character.isWhitespace || character.isPunctuation || character.isSymbol
        }
        .map(String.init)
        .filter { !$0.isEmpty }
    }

    var kidoXSearchInitials: String {
        kidoXSearchTokens.compactMap(\.first).map(String.init).joined()
    }

    func kidoXSubsequenceScore(for query: String) -> Int? {
        var haystackIndex = startIndex
        var previousMatch: String.Index?
        var gapPenalty = 0

        for needle in query {
            guard let matchIndex = self[haystackIndex...].firstIndex(of: needle) else {
                return nil
            }
            if let previousMatch {
                gapPenalty += distance(from: index(after: previousMatch), to: matchIndex)
            } else {
                gapPenalty += distance(from: startIndex, to: matchIndex)
            }
            haystackIndex = index(after: matchIndex)
            previousMatch = matchIndex
        }

        return min(gapPenalty, 24) + min(count - query.count, 12)
    }

    func kidoXEditDistance(to other: String, limit: Int) -> Int? {
        let source = Array(self)
        let target = Array(other)
        guard abs(source.count - target.count) <= limit else { return nil }
        if source.isEmpty { return target.count <= limit ? target.count : nil }
        if target.isEmpty { return source.count <= limit ? source.count : nil }

        var previous = Array(0...target.count)
        var current = Array(repeating: 0, count: target.count + 1)

        for sourceIndex in 1...source.count {
            current[0] = sourceIndex
            var rowMinimum = current[0]

            for targetIndex in 1...target.count {
                let substitutionCost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1
                current[targetIndex] = Swift.min(
                    previous[targetIndex] + 1,
                    current[targetIndex - 1] + 1,
                    previous[targetIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[targetIndex])
            }

            guard rowMinimum <= limit else { return nil }
            swap(&previous, &current)
        }

        let distance = previous[target.count]
        return distance <= limit ? distance : nil
    }
}
