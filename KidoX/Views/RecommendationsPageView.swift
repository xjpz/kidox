import SwiftUI

/// Populated recommendations deliberately have no heading or explanatory subtitle.
struct RecommendationsEmptyView: View {
    @AppStorage(KidoXLanguage.storageKey) private var appLanguageRaw = KidoXLanguage.system.rawValue
    let isLoading: Bool
    let hasExclusions: Bool
    let onManage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "star")
                    .font(.system(size: 28, weight: .light))
                Text(KidoXL10n.ui("No frequent apps yet"))
                    .font(.system(size: 15))
                if hasExclusions {
                    Button(KidoXL10n.ui("Manage excluded apps"), action: onManage)
                        .buttonStyle(.plain)
                        .underline()
                }
            }
        }
        .foregroundStyle(.white.opacity(0.72))
        .id(appLanguageRaw)
    }
}
