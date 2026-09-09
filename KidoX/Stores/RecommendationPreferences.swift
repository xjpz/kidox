import Foundation
import Observation

enum RecommendationLayout: String, Codable, CaseIterable, Identifiable {
    case sixByFour = "6x4"
    case sevenByFive = "7x5"

    var id: String { rawValue }
    var columns: Int { self == .sixByFour ? 6 : 7 }
    var rows: Int { self == .sixByFour ? 4 : 5 }
    var capacity: Int { columns * rows }
}

struct RecommendationExclusion: Codable, Equatable, Identifiable {
    var applicationKey: String
    var displayName: String
    var id: String { applicationKey }
}

/// Encodes into the existing backup preferences object, with defaults for older backups.
struct RecommendationBackupPreferences: Codable, Equatable {
    var recommendationsEnabled = true
    var recommendationLayout: RecommendationLayout = .sixByFour
    var recommendationExclusions: [RecommendationExclusion] = []

    init(enabled: Bool = true, layout: RecommendationLayout = .sixByFour, exclusions: [RecommendationExclusion] = []) {
        recommendationsEnabled = enabled
        recommendationLayout = layout
        recommendationExclusions = exclusions
    }

    private enum CodingKeys: String, CodingKey {
        case recommendationsEnabled, recommendationLayout, recommendationExclusions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .recommendationsEnabled) ?? true
        let layoutRaw = try container.decodeIfPresent(String.self, forKey: .recommendationLayout)
        recommendationLayout = layoutRaw.flatMap(RecommendationLayout.init(rawValue:)) ?? .sixByFour
        recommendationExclusions = try container.decodeIfPresent([RecommendationExclusion].self, forKey: .recommendationExclusions) ?? []
    }
}

@MainActor
@Observable
final class RecommendationPreferences {
    static let shared = RecommendationPreferences()
    static let enabledKey = "KidoX.recommendations.enabled"
    static let layoutKey = "KidoX.recommendations.layout"
    static let exclusionsKey = "KidoX.recommendations.exclusions"
    static let didChange = Notification.Name("KidoX.recommendations.didChange")
    var showsExclusions = false
    var requestsManagement = false

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            notifyChange()
        }
    }
    var layout: RecommendationLayout {
        didSet {
            guard oldValue != layout else { return }
            defaults.set(layout.rawValue, forKey: Self.layoutKey)
            notifyChange()
        }
    }
    private(set) var exclusions: [RecommendationExclusion] {
        didSet {
            guard oldValue != exclusions else { return }
            if let data = try? JSONEncoder().encode(exclusions) {
                defaults.set(data, forKey: Self.exclusionsKey)
            }
            notifyChange()
        }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        layout = defaults.string(forKey: Self.layoutKey).flatMap(RecommendationLayout.init(rawValue:)) ?? .sixByFour
        exclusions = defaults.data(forKey: Self.exclusionsKey)
            .flatMap { try? JSONDecoder().decode([RecommendationExclusion].self, from: $0) } ?? []
    }

    var excludedKeys: Set<String> { Set(exclusions.map(\.applicationKey)) }
    var backup: RecommendationBackupPreferences {
        RecommendationBackupPreferences(enabled: isEnabled, layout: layout, exclusions: exclusions)
    }

    func exclude(_ item: LaunchItem) {
        let key = ApplicationRecommendationEngine.key(for: item)
        guard !excludedKeys.contains(key) else { return }
        exclusions.append(RecommendationExclusion(applicationKey: key, displayName: item.effectiveDisplayName))
    }

    func restore(_ key: String) { exclusions.removeAll { $0.applicationKey == key } }
    func restoreAll() { exclusions.removeAll() }

    func apply(_ backup: RecommendationBackupPreferences) {
        isEnabled = backup.recommendationsEnabled
        layout = backup.recommendationLayout
        var seen = Set<String>()
        exclusions = backup.recommendationExclusions.filter { seen.insert($0.applicationKey).inserted }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
