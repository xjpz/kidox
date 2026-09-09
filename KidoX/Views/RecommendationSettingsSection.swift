import SwiftUI

struct RecommendationSettingsSection: View {
    @AppStorage(KidoXLanguage.storageKey) private var appLanguageRaw = KidoXLanguage.system.rawValue
    @Bindable private var preferences = RecommendationPreferences.shared
    @State private var installedKeys: Set<String>?

    var body: some View {
        Section {
            Toggle(KidoXL10n.ui("Show frequent apps page"), isOn: $preferences.isEnabled)
            Picker(KidoXL10n.ui("Frequent apps layout"), selection: $preferences.layout) {
                Text(KidoXL10n.ui("6 × 4 (up to 24 apps)")).tag(RecommendationLayout.sixByFour)
                Text(KidoXL10n.ui("7 × 5 (up to 35 apps)")).tag(RecommendationLayout.sevenByFive)
            }
            .pickerStyle(.menu)
            .disabled(!preferences.isEnabled)
            Text(KidoXL10n.ui("Available with Default sorting. Only launches from KidoX are counted."))
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $preferences.showsExclusions) {
                if preferences.exclusions.isEmpty {
                    Text(KidoXL10n.ui("No excluded apps"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.exclusions) { exclusion in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exclusion.displayName).lineLimit(1)
                                if let installedKeys, !installedKeys.contains(exclusion.applicationKey) {
                                    Text(KidoXL10n.ui("Not installed"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(KidoXL10n.ui("Restore recommendation")) {
                                preferences.restore(exclusion.applicationKey)
                            }
                            .controlSize(.small)
                        }
                    }
                    Button(KidoXL10n.ui("Restore all recommendations")) { preferences.restoreAll() }
                    Text(KidoXL10n.ui("Restored apps can appear the next time you open KidoX."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } label: {
                Text(KidoXL10n.uiFormat("Excluded apps (%d)", preferences.exclusions.count))
            }
            .task(id: preferences.showsExclusions) {
                guard preferences.showsExclusions, !preferences.exclusions.isEmpty else { return }
                let items = await ApplicationScanner().scan()
                guard !Task.isCancelled else { return }
                installedKeys = Set(items.map(ApplicationRecommendationEngine.key(for:)))
            }
        } header: {
            Text(KidoXL10n.ui("Frequent Apps"))
        }
        .listRowBackground(Color(nsColor: .controlBackgroundColor))
        .id(appLanguageRaw)
    }
}
