import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PinApplicationMenu: View {
    let item: LaunchItem
    @Bindable private var preferences = RecommendationPreferences.shared
    var body: some View {
        if item.kind == .application {
            Button(KidoXL10n.ui(preferences.isPinned(item) ? "Unpin app" : "Pin to Frequent Apps")) {
                if preferences.isPinned(item) { preferences.unpin(ApplicationRecommendationEngine.key(for: item)) }
                else { pinApplication(item) }
            }
            .disabled(!preferences.isPinned(item) && !preferences.canPinMore)
            if !preferences.canPinMore && !preferences.isPinned(item) {
                Text(KidoXL10n.ui("Pinned apps are full. Change the layout or manage pins."))
            }
        }
    }
}

struct PinnedApplicationsSettings: View {
    @Bindable private var preferences = RecommendationPreferences.shared
    @State private var applications: [LaunchItem] = []
    @State private var hiddenKeys: Set<String> = []
    @State private var didLoadApplications = false

    var body: some View {
        DisclosureGroup(isExpanded: $preferences.showsPins) {
            if preferences.pins.isEmpty {
                Text(KidoXL10n.ui("Right-click an app to pin it to Frequent Apps."))
                    .foregroundStyle(.secondary)
            }
            ForEach(preferences.pins) { pin in
                HStack(spacing: 10) {
                    if let app = applications.first(where: { ApplicationRecommendationEngine.key(for: $0) == pin.id }) {
                        Image(nsImage: IconCache.icon(for: app.sourcePath)).resizable().frame(width: 24, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.displayName).lineLimit(1)
                        if didLoadApplications && !applications.contains(where: { ApplicationRecommendationEngine.key(for: $0) == pin.id }) {
                            Text(KidoXL10n.ui("Not installed")).font(.caption).foregroundStyle(.secondary)
                        } else if hiddenKeys.contains(pin.id) {
                            Text(KidoXL10n.ui("Hidden")).font(.caption).foregroundStyle(.secondary)
                        }
                        if isOutsideLayout(pin.id) {
                            Text(KidoXL10n.ui("Outside the current layout")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(KidoXL10n.ui("Unpin app")) { preferences.unpin(pin.id) }
                }
                .controlSize(.small)
            }
        } label: {
            Text(KidoXL10n.uiFormat("Pinned apps (%d)", preferences.pins.count))
        }
        .task(id: preferences.showsPins) {
            guard preferences.showsPins else { return }
            applications = await ApplicationScanner().scan()
            let items = await KidoXDatabase().loadPagesAsync().flatMap(\.items)
            let hiddenFolders = Set(items.filter { $0.kind == .folder && $0.isHidden }.map(\.id))
            hiddenKeys = Set(items.filter { $0.isHidden || $0.parentID.map(hiddenFolders.contains) == true }
                .map(ApplicationRecommendationEngine.key(for:)))
            didLoadApplications = true
        }
    }

    private func isOutsideLayout(_ key: String) -> Bool {
        let installed = Set(applications.map(ApplicationRecommendationEngine.key(for:)))
        let visiblePins = preferences.pins.filter { installed.contains($0.id) && !hiddenKeys.contains($0.id) }
        return visiblePins.firstIndex(where: { $0.id == key }).map { $0 >= preferences.layout.capacity } ?? false
    }
}

@MainActor
func pinApplication(_ item: LaunchItem) {
    let preferences = RecommendationPreferences.shared
    guard preferences.pin(item), preferences.isEnabled else { return }
    let defaults = UserDefaults.standard
    let sort = KidoXLaunchSort(rawValue: defaults.string(forKey: KidoXLaunchSort.storageKey) ?? "") ?? .default
    if sort != .default && defaults.string(forKey: "ClyAppLicense.status") == "active" {
        preferences.feedback = "Pinned. Frequent Apps is available with Default sorting."
    }
}

@MainActor
func acceptPinDrop(_ providers: [NSItemProvider], before key: String?) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let source = object as? String else { return }
        Task { @MainActor in
            guard RecommendationPreferences.shared.pinnedKeys.contains(source) else { return }
            RecommendationPreferences.shared.movePin(source, before: key)
        }
    }
    return true
}
