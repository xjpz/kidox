import Foundation

/// Reads the existing application records; never owns or writes usage statistics.
enum ApplicationRecommendationEngine {
    static let limit = 24

    static func key(for item: LaunchItem) -> String {
        item.bundleIdentifier ?? item.sourcePath
    }

    static func eligibleItems(
        in items: [LaunchItem],
        excluding excludedKeys: Set<String> = [],
        unavailableKeys: Set<String> = []
    ) -> [String: LaunchItem] {
        var hiddenFolders = Set<UUID>()
        for item in items where item.kind == .folder && item.isHidden { hiddenFolders.insert(item.id) }
        var blocked = excludedKeys.union(unavailableKeys)
        for item in items where item.kind == .application {
            if item.isHidden || item.parentID.map(hiddenFolders.contains) == true { blocked.insert(key(for: item)) }
        }
        var candidates: [String: LaunchItem] = [:]
        for item in items where item.kind == .application && item.openCount > 0 {
            let key = key(for: item)
            guard !blocked.contains(key) else { continue }
            if let existing = candidates[key], !precedes(item, existing) { continue }
            candidates[key] = item
        }
        return candidates
    }

    static func rankedKeys(in items: [LaunchItem], excluding: Set<String> = [], limit: Int = limit) -> [String] {
        // Sorting LaunchItem itself repeatedly copies its many strings and URL fields.
        // Keep the hot comparison/swap path limited to the three ranking values.
        eligibleItems(in: items, excluding: excluding)
            .map { RankingEntry(key: $0.key, count: $0.value.openCount, date: $0.value.lastOpenedAt ?? .distantPast) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.key < $1.key
            }
            .prefix(max(0, limit))
            .map(\.key)
    }

    private struct RankingEntry {
        let key: String
        let count: Int
        let date: Date
    }

    private static func precedes(_ lhs: LaunchItem, _ rhs: LaunchItem) -> Bool {
        if lhs.openCount != rhs.openCount { return lhs.openCount > rhs.openCount }
        let lhsDate = lhs.lastOpenedAt ?? .distantPast
        let rhsDate = rhs.lastOpenedAt ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        let lhsKey = key(for: lhs)
        let rhsKey = key(for: rhs)
        if lhsKey != rhsKey { return lhsKey < rhsKey }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Removal is immediate and permanent within a session; restoration/backfill waits for the next one.
struct ApplicationRecommendationSnapshot {
    private(set) var keys: [String] = []
    private(set) var isReady = false

    mutating func begin(items: [LaunchItem], excluding: Set<String>, dataIsReady: Bool, limit: Int = ApplicationRecommendationEngine.limit) {
        isReady = dataIsReady
        keys = dataIsReady ? ApplicationRecommendationEngine.rankedKeys(in: items, excluding: excluding, limit: limit) : []
    }

    mutating func resolve(items: [LaunchItem], excluding: Set<String>, unavailable: Set<String> = []) -> [LaunchItem] {
        let candidates = ApplicationRecommendationEngine.eligibleItems(
            in: items, excluding: excluding, unavailableKeys: unavailable
        )
        keys.removeAll { candidates[$0] == nil }
        return keys.compactMap { candidates[$0] }
    }
}
