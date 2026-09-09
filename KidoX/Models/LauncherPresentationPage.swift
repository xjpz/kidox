import Foundation

enum SearchSelectionMove {
    case up, down, left, right
}

enum LauncherPageID: Hashable {
    case recommendations
    case layout(UUID)
    case emptyHome
    case results(context: String, index: Int)

    var isRecommendations: Bool { self == .recommendations }
    var layoutID: UUID? {
        if case .layout(let id) = self { return id }
        return nil
    }
}

struct PresentedItemID: Hashable {
    let pageID: LauncherPageID
    let itemID: LaunchItem.ID
}

struct LauncherPresentationPage: Equatable {
    let id: LauncherPageID
    let items: [LaunchItem]
}

/// Owned by the store so closing or rebuilding the panel does not lose its place.
struct LauncherNavigationState {
    var pageID: LauncherPageID?
    var pageBeforeSearch: LauncherPageID?

    mutating func resumeBrowsing() {
        if let pageBeforeSearch { pageID = pageBeforeSearch }
        pageBeforeSearch = nil
    }
}

/// The only translation between animated display positions and persisted layout pages.
struct LauncherPageProjection {
    let pages: [LauncherPresentationPage]

    init(layoutPages: [LaunchPage], recommendations: [LaunchItem]?) {
        var projected = layoutPages.sorted { $0.sortIndex < $1.sortIndex }.map {
            LauncherPresentationPage(id: .layout($0.id), items: $0.rootItems)
        }
        if projected.isEmpty { projected = [LauncherPresentationPage(id: .emptyHome, items: [])] }
        if let recommendations {
            projected.insert(LauncherPresentationPage(id: .recommendations, items: recommendations), at: 0)
        }
        pages = projected
    }

    init(results: [[LaunchItem]], context: String) {
        pages = (results.isEmpty ? [[]] : results).enumerated().map {
            LauncherPresentationPage(id: .results(context: context, index: $0.offset), items: $0.element)
        }
    }

    var ids: [LauncherPageID] { pages.map(\.id) }
    var items: [[LaunchItem]] { pages.map(\.items) }
    var homeIndex: Int { pages.firstIndex { !$0.id.isRecommendations } ?? 0 }

    func id(at index: Int) -> LauncherPageID? {
        pages.indices.contains(index) ? pages[index].id : nil
    }

    func index(of id: LauncherPageID?) -> Int? {
        guard let id else { return nil }
        return pages.firstIndex { $0.id == id }
    }

    func restoredIndex(for id: LauncherPageID?) -> Int {
        index(of: id) ?? homeIndex
    }

    func layoutPosition(for id: LauncherPageID?, in currentPages: [LaunchPage]) -> Int? {
        guard let layoutID = id?.layoutID else { return nil }
        return currentPages.sorted { $0.sortIndex < $1.sortIndex }.firstIndex { $0.id == layoutID }
    }

    func searchDragDestination(from source: LauncherPageID?) -> LauncherPageID? {
        if source?.layoutID != nil, index(of: source) != nil { return source }
        return id(at: homeIndex)
    }

    func movingSelection(
        on pageID: LauncherPageID, selectedItemID: LaunchItem.ID?,
        direction: SearchSelectionMove, recommendationLayout: RecommendationLayout = .sixByFour
    ) -> PresentedItemID? {
        guard let pageIndex = index(of: pageID), !pages[pageIndex].items.isEmpty else { return nil }
        let items = pages[pageIndex].items
        guard let selectedItemID, let itemIndex = items.firstIndex(where: { $0.id == selectedItemID }) else {
            guard direction == .right || direction == .down else { return nil }
            return PresentedItemID(pageID: pageID, itemID: items[0].id)
        }
        let columns = pageID.isRecommendations ? recommendationLayout.columns : 7
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -columns
        case .down: delta = columns
        }
        let candidate = itemIndex + delta
        if !pageID.isRecommendations && (candidate < 0 || candidate >= items.count) {
            let step = delta < 0 ? -1 : 1
            var next = pageIndex + step
            while pages.indices.contains(next), !pages[next].id.isRecommendations {
                if let item = pages[next].items.first {
                    return PresentedItemID(pageID: pages[next].id, itemID: item.id)
                }
                next += step
            }
        }
        return PresentedItemID(pageID: pageID, itemID: items[max(0, min(candidate, items.count - 1))].id)
    }
}

/// Shared slot positions keep recommendation and ordinary pages aligned.
enum LauncherGridLayout {
    static func x(index: Int, columns: Int, width: CGFloat, margin: CGFloat) -> CGFloat {
        let columns = max(columns, 1)
        let slotWidth = max(width - margin * 2, 1) / CGFloat(columns)
        return margin + slotWidth * (CGFloat(index % columns) + 0.5)
    }

    static func y(index: Int, columns: Int, rows: Int, top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard rows > 1 else { return (top + bottom) / 2 }
        let row = CGFloat(index / max(columns, 1))
        return top + ((bottom - top) / CGFloat(rows - 1)) * row
    }
}

/// Fixed capacity; sparse rows retain their leftmost slots.
enum RecommendationGridLayout {
    static func center(
        index: Int, width: CGFloat, margin: CGFloat, top: CGFloat,
        tileWidth: CGFloat, tileHeight: CGFloat, layout: RecommendationLayout = .sixByFour
    ) -> CGPoint {
        let columns = layout.columns
        let availableWidth = max(width - margin * 2, 1)
        let columnStride = min(tileWidth + 20, availableWidth / CGFloat(columns))
        let rowStride = tileHeight + 32
        // Center the selected grid region, never individual partial rows.
        let leading = (width - columnStride * CGFloat(columns)) / 2
        return CGPoint(
            x: leading + columnStride * (CGFloat(index % columns) + 0.5),
            y: top + rowStride * CGFloat(index / columns)
        )
    }
}
