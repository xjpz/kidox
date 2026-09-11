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
    var pinnedApplications: [RecommendationExclusion] = []

    init(enabled: Bool = true, layout: RecommendationLayout = .sixByFour, exclusions: [RecommendationExclusion] = [], pins: [RecommendationExclusion] = []) {
        recommendationsEnabled = enabled
        recommendationLayout = layout
        recommendationExclusions = exclusions
        pinnedApplications = pins
    }

    private enum CodingKeys: String, CodingKey {
        case recommendationsEnabled, recommendationLayout, recommendationExclusions, pinnedApplications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .recommendationsEnabled) ?? true
        let layoutRaw = try container.decodeIfPresent(String.self, forKey: .recommendationLayout)
        recommendationLayout = layoutRaw.flatMap(RecommendationLayout.init(rawValue:)) ?? .sixByFour
        recommendationExclusions = try container.decodeIfPresent([RecommendationExclusion].self, forKey: .recommendationExclusions) ?? []
        pinnedApplications = try container.decodeIfPresent([RecommendationExclusion].self, forKey: .pinnedApplications) ?? []
    }
}

@MainActor
@Observable
final class RecommendationPreferences {
    static let shared = RecommendationPreferences()
    static let enabledKey = "KidoX.recommendations.enabled"
    static let layoutKey = "KidoX.recommendations.layout"
    static let exclusionsKey = "KidoX.recommendations.exclusions"
    static let pinsKey = "KidoX.recommendations.pins"
    static let didChange = Notification.Name("KidoX.recommendations.didChange")
    var showsExclusions = false
    var showsPins = false
    var feedback: String?
    private(set) var pins: [RecommendationExclusion] = []
    @ObservationIgnored private var isUpdating = false
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
        pins = Self.normalizedPins(defaults.data(forKey: Self.pinsKey)
            .flatMap { try? JSONDecoder().decode([RecommendationExclusion].self, from: $0) } ?? [])
        let pinned = pinnedKeys
        exclusions.removeAll { pinned.contains($0.applicationKey) }
    }

    var pinnedKeys: Set<String> { Set(pins.map(\.applicationKey)) }
    var canPinMore: Bool { pins.count < layout.capacity }
    func isPinned(_ item: LaunchItem) -> Bool { pinnedKeys.contains(ApplicationRecommendationEngine.key(for: item)) }

    @discardableResult
    func pin(_ item: LaunchItem) -> Bool {
        guard item.kind == .application, !isPinned(item), canPinMore else { return false }
        isUpdating = true
        let key = ApplicationRecommendationEngine.key(for: item)
        exclusions.removeAll { $0.applicationKey == key }
        pins.append(.init(applicationKey: key, displayName: item.effectiveDisplayName))
        isUpdating = false
        savePins()
        feedback = isEnabled ? nil : "Pinned. Enable Frequent Apps to show it."
        return true
    }

    func unpin(_ key: String) {
        pins.removeAll { $0.applicationKey == key }
        savePins()
        feedback = "Unpinned. This app may still appear in Frequent Apps."
    }

    func movePin(_ key: String, before destination: String?) {
        guard key != destination, let index = pins.firstIndex(where: { $0.applicationKey == key }) else { return }
        let entry = pins.remove(at: index)
        let target = destination.flatMap { key in pins.firstIndex { $0.applicationKey == key } } ?? pins.endIndex
        pins.insert(entry, at: target)
        savePins()
    }

    func movePin(_ key: String, by offset: Int) {
        guard let index = pins.firstIndex(where: { $0.applicationKey == key }) else { return }
        let target = min(max(index + offset, 0), pins.count - 1)
        guard target != index else { return }
        pins.insert(pins.remove(at: index), at: target)
        savePins()
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: Self.pinsKey) }
        notifyChange()
    }

    private static func normalizedPins(_ values: [RecommendationExclusion]) -> [RecommendationExclusion] {
        var seen = Set<String>()
        return Array(values.filter { !$0.applicationKey.isEmpty && seen.insert($0.applicationKey).inserted }.prefix(35))
    }

    var excludedKeys: Set<String> { Set(exclusions.map(\.applicationKey)) }
    var backup: RecommendationBackupPreferences {
        RecommendationBackupPreferences(enabled: isEnabled, layout: layout, exclusions: exclusions, pins: pins)
    }

    func exclude(_ item: LaunchItem) {
        let key = ApplicationRecommendationEngine.key(for: item)
        guard !pinnedKeys.contains(key), !excludedKeys.contains(key) else { return }
        exclusions.append(RecommendationExclusion(applicationKey: key, displayName: item.effectiveDisplayName))
    }

    func restore(_ key: String) { exclusions.removeAll { $0.applicationKey == key } }
    func restoreAll() { exclusions.removeAll() }

    func apply(_ backup: RecommendationBackupPreferences) {
        isUpdating = true
        pins = Self.normalizedPins(backup.pinnedApplications)
        isEnabled = backup.recommendationsEnabled
        layout = backup.recommendationLayout
        var seen = Set<String>()
        exclusions = backup.recommendationExclusions.filter { !pinnedKeys.contains($0.applicationKey) && seen.insert($0.applicationKey).inserted }
        isUpdating = false
        savePins()
    }

    private func notifyChange() {
        guard !isUpdating else { return }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
