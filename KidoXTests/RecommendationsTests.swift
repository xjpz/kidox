import XCTest

final class RecommendationsTests: XCTestCase {
    private func app(_ key: String, count: Int = 1, date: Date? = nil, parent: UUID? = nil) -> LaunchItem {
        LaunchItem(kind: .application, displayName: key, subtitle: "", url: URL(fileURLWithPath: "/Applications/\(key).app"),
                   bundleIdentifier: key, sourcePath: "/Applications/\(key).app", lastOpenedAt: date, openCount: count, parentID: parent)
    }

    func testFrequencyThenRecencyThenStableKey() {
        let items = [app("z", count: 9), app("b", count: 2, date: Date(timeIntervalSince1970: 10)),
                     app("c", count: 2), app("a", count: 2, date: Date(timeIntervalSince1970: 10))]
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: items), ["z", "a", "b", "c"])
    }

    func testNilAndDistantPastTieUsesKey() {
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: [app("b"), app("a", date: .distantPast)]), ["a", "b"])
    }

    func testTwentyFourItemLimitAndNoPadding() {
        let candidates = (0..<40).map { app("\($0)", count: $0 + 1) }
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: candidates), (16..<40).reversed().map { "\($0)" })
        let fewerCandidates = Array(candidates.prefix(20))
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: fewerCandidates).count, 20)
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: [app("one")]), ["one"])
        XCTAssertTrue(ApplicationRecommendationEngine.rankedKeys(in: []).isEmpty)
        XCTAssertTrue(ApplicationRecommendationEngine.rankedKeys(in: [app("a")], limit: -1).isEmpty)
    }

    func testCandidateKindsVisibilityAndFolderChildren() {
        var folder = app("folder"); folder.kind = .folder
        var hiddenFolder = app("hiddenFolder"); hiddenFolder.kind = .folder; hiddenFolder.isHidden = true
        var hidden = app("hidden"); hidden.isHidden = true
        var file = app("file"); file.kind = .file
        var url = app("url"); url.kind = .url
        let items = [folder, hiddenFolder, hidden, file, url, app("zero", count: 0), app("excluded"),
                     app("child", parent: folder.id), app("hiddenChild", parent: hiddenFolder.id)]
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: items, excluding: ["excluded"]), ["child"])
    }

    func testDuplicateKeysSelectOneOriginalWithoutAddingCounts() {
        let first = app("a", count: 5)
        let second = app("a", count: 8)
        let selected = ApplicationRecommendationEngine.eligibleItems(in: [first, second])["a"]
        XCTAssertEqual(selected?.id, second.id)
        XCTAssertEqual(selected?.openCount, 8)
    }

    func testDuplicateHiddenRecordSuppressesAllCopies() {
        let visible = app("same", count: 10)
        var hidden = app("same"); hidden.isHidden = true
        XCTAssertTrue(ApplicationRecommendationEngine.rankedKeys(in: [visible, hidden]).isEmpty)
    }

    func testPathFallbackIdentity() {
        var first = app("one"); first.bundleIdentifier = nil
        var second = first; second.displayName = "renamed"
        XCTAssertEqual(ApplicationRecommendationEngine.key(for: first), first.sourcePath)
        XCTAssertEqual(ApplicationRecommendationEngine.rankedKeys(in: [first, second]), [first.sourcePath])
    }

    func testSnapshotFreezesUsageOrderUntilNextSession() {
        var a = app("a", count: 3), b = app("b", count: 2)
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [a, b], excluding: [], dataIsReady: true)
        b.openCount = 100; a.displayName = "renamed"
        let resolved = snapshot.resolve(items: [b, a], excluding: [])
        XCTAssertEqual(resolved.map(\.id), [a.id, b.id])
        XCTAssertEqual(resolved.first?.displayName, "renamed")
        snapshot.begin(items: [a, b], excluding: [], dataIsReady: true)
        XCTAssertEqual(snapshot.keys, ["b", "a"])
    }

    func testExclusionRestorationDoesNotBackfillThisSession() {
        let a = app("a"), b = app("b")
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [a, b], excluding: [], dataIsReady: true)
        XCTAssertEqual(snapshot.resolve(items: [a, b], excluding: ["a"]).map(\.id), [b.id])
        XCTAssertEqual(snapshot.resolve(items: [a, b], excluding: []).map(\.id), [b.id])
        snapshot.begin(items: [a, b], excluding: [], dataIsReady: true)
        XCTAssertEqual(snapshot.keys, ["a", "b"])
    }

    func testRemovedAndUnavailableAppsDisappearWithoutBackfill() {
        let a = app("a"), b = app("b"), c = app("c", count: 100)
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [a, b], excluding: [], dataIsReady: true)
        XCTAssertEqual(snapshot.resolve(items: [a, b, c], excluding: [], unavailable: ["a"]).map(\.id), [b.id])
        XCTAssertTrue(snapshot.resolve(items: [a, c], excluding: []).isEmpty)
    }

    func testColdSnapshotWaitsForLoadedData() {
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [], excluding: [], dataIsReady: false)
        XCTAssertFalse(snapshot.isReady)
        XCTAssertTrue(snapshot.resolve(items: [app("a")], excluding: []).isEmpty)
        snapshot.begin(items: [app("a")], excluding: [], dataIsReady: true)
        XCTAssertTrue(snapshot.isReady)
        XCTAssertEqual(snapshot.keys, ["a"])
    }

    func testProjectionKeepsHomeAndRealPositionsSeparate() {
        let item = app("a")
        let pages = [LaunchPage(sortIndex: 0, items: [item]), LaunchPage(sortIndex: 1)]
        let projection = LauncherPageProjection(layoutPages: pages, recommendations: [item])
        XCTAssertEqual(projection.homeIndex, 1)
        XCTAssertEqual(projection.id(at: 0), .recommendations)
        XCTAssertNil(projection.layoutPosition(for: .recommendations, in: pages))
        XCTAssertEqual(projection.layoutPosition(for: projection.id(at: 1), in: pages), 0)
        XCTAssertEqual(projection.layoutPosition(for: projection.id(at: 2), in: pages), 1)
        XCTAssertEqual(pages[0].items, [item])
    }

    func testReopeningKeepsLastOrdinaryRecommendationAndSortedPage() {
        let first = LaunchPage(sortIndex: 0), second = LaunchPage(sortIndex: 1)
        let layout = LauncherPageProjection(layoutPages: [first, second], recommendations: [])
        for pageID in [LauncherPageID.layout(second.id), .recommendations] {
            var navigation = LauncherNavigationState(pageID: pageID)
            navigation.resumeBrowsing()
            navigation.resumeBrowsing()
            XCTAssertEqual(navigation.pageID, pageID)
            XCTAssertEqual(layout.id(at: layout.restoredIndex(for: navigation.pageID)), pageID)
        }
        let sorted = LauncherPageProjection(results: [[app("a")], [app("b")]], context: "name:")
        var navigation = LauncherNavigationState(pageID: sorted.id(at: 1))
        navigation.resumeBrowsing()
        XCTAssertEqual(sorted.restoredIndex(for: navigation.pageID), 1)
    }

    func testReopeningFromSearchRestoresOriginBeforeTheViewReturns() {
        let originalPage = LauncherPageID.layout(UUID())
        for origin in [originalPage, .recommendations] {
            var navigation = LauncherNavigationState(
                pageID: .results(context: "default:query", index: 0), pageBeforeSearch: origin
            )
            navigation.resumeBrowsing()
            XCTAssertEqual(navigation.pageID, origin)
            XCTAssertNil(navigation.pageBeforeSearch)
            // A repeated show or later search-clear callback must not reset the restored page.
            navigation.resumeBrowsing()
            XCTAssertEqual(navigation.pageID, origin)
        }
    }

    func testRestoredPageSurvivesInsertionAndFallsBackWhenUnavailable() {
        let first = LaunchPage(sortIndex: 0), remembered = LaunchPage(sortIndex: 2)
        var navigation = LauncherNavigationState(pageID: .layout(remembered.id))
        navigation.resumeBrowsing()
        let inserted = LaunchPage(sortIndex: 1)
        let expanded = LauncherPageProjection(layoutPages: [first, inserted, remembered], recommendations: [])
        XCTAssertEqual(expanded.restoredIndex(for: navigation.pageID), 3)
        let removed = LauncherPageProjection(layoutPages: [first, inserted], recommendations: [])
        XCTAssertEqual(removed.restoredIndex(for: navigation.pageID), removed.homeIndex)

        navigation.pageID = .recommendations
        let disabled = LauncherPageProjection(layoutPages: [first, remembered], recommendations: nil)
        XCTAssertEqual(disabled.restoredIndex(for: navigation.pageID), disabled.homeIndex)
        navigation.pageBeforeSearch = .layout(remembered.id)
        navigation.resumeBrowsing()
        XCTAssertEqual(removed.restoredIndex(for: navigation.pageID), removed.homeIndex)
    }

    func testFreshNavigationStartsAtRealHome() {
        var navigation = LauncherNavigationState()
        navigation.resumeBrowsing()
        let projection = LauncherPageProjection(layoutPages: [LaunchPage(sortIndex: 0)], recommendations: [])
        XCTAssertEqual(projection.restoredIndex(for: navigation.pageID), 1)
    }

    func testRepeatedAppHasDistinctPresentationIdentity() {
        let item = app("a"), page = UUID()
        let ids: Set<PresentedItemID> = [PresentedItemID(pageID: .recommendations, itemID: item.id),
                                       PresentedItemID(pageID: .layout(page), itemID: item.id)]
        XCTAssertEqual(ids.count, 2)
    }

    func testKeyboardSelectionDoesNotJumpToAnotherCopyOfTheApp() {
        let first = app("a"), second = app("b")
        let page = LaunchPage(sortIndex: 0, items: [first, second])
        let projection = LauncherPageProjection(layoutPages: [page], recommendations: [first, second])
        let result = projection.movingSelection(on: .layout(page.id), selectedItemID: first.id, direction: .right)
        XCTAssertEqual(result, PresentedItemID(pageID: .layout(page.id), itemID: second.id))
        let boundary = projection.movingSelection(on: .layout(page.id), selectedItemID: first.id, direction: .left)
        XCTAssertEqual(boundary?.pageID, .layout(page.id))
    }

    func testRecommendationArrowsRespectColumnsAndStayOnTheirPage() {
        let items = (0..<24).map { app("\($0)") }
        let projection = LauncherPageProjection(layoutPages: [LaunchPage(sortIndex: 0, items: items)], recommendations: items)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[0].id,
            direction: .down)?.itemID, items[6].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[18].id,
            direction: .up)?.itemID, items[12].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[17].id,
            direction: .down)?.itemID, items[23].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[23].id,
            direction: .down)?.itemID, items[23].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items.last!.id,
            direction: .right), PresentedItemID(pageID: .recommendations, itemID: items.last!.id))
    }

    func testKeyboardNavigationStillCrossesOrdinaryPagesAndSkipsEmptyOnes() {
        let a = app("a"), b = app("b")
        let first = LaunchPage(sortIndex: 0, items: [a]), empty = LaunchPage(sortIndex: 1), last = LaunchPage(sortIndex: 2, items: [b])
        let projection = LauncherPageProjection(layoutPages: [first, empty, last], recommendations: [b])
        XCTAssertEqual(projection.movingSelection(on: .layout(first.id), selectedItemID: a.id, direction: .right),
                       PresentedItemID(pageID: .layout(last.id), itemID: b.id))
    }

    func testPageIdentitySurvivesInsertionRemovalAndToggle() {
        let original = LaunchPage(sortIndex: 1)
        let inserted = LaunchPage(sortIndex: 0)
        let enabled = LauncherPageProjection(layoutPages: [original], recommendations: [])
        let changed = LauncherPageProjection(layoutPages: [original, inserted], recommendations: [])
        XCTAssertEqual(enabled.index(of: .layout(original.id)), 1)
        XCTAssertEqual(changed.index(of: .layout(original.id)), 2)
        XCTAssertEqual(changed.layoutPosition(for: .layout(original.id), in: [original]), 0)
        XCTAssertNil(changed.layoutPosition(for: .layout(inserted.id), in: [original]))
        let disabled = LauncherPageProjection(layoutPages: [original], recommendations: nil)
        XCTAssertEqual(disabled.index(of: .layout(original.id)), 0)
        XCTAssertEqual(disabled.homeIndex, 0)
        XCTAssertNil(disabled.index(of: .recommendations))
    }

    func testSearchHasNoRecommendationDuplicateAndRestoresSourceID() {
        let item = app("a")
        let page = LaunchPage(sortIndex: 0, items: [item])
        let layout = LauncherPageProjection(layoutPages: [page], recommendations: [item])
        let source = layout.id(at: 0)
        let search = LauncherPageProjection(results: [[item]], context: "query")
        XCTAssertEqual(search.items.flatMap { $0 }.count, 1)
        XCTAssertEqual(search.homeIndex, 0)
        XCTAssertNil(search.index(of: source))
        XCTAssertEqual(layout.index(of: source), 0)
        XCTAssertNil(search.layoutPosition(for: search.id(at: 0), in: [page]))
    }

    func testSearchDragFromRecommendationOrDeletedPageUsesRealHome() {
        let first = LaunchPage(sortIndex: 0), second = LaunchPage(sortIndex: 1)
        let projection = LauncherPageProjection(layoutPages: [first, second], recommendations: [])
        XCTAssertEqual(projection.searchDragDestination(from: .recommendations), .layout(first.id))
        XCTAssertEqual(projection.searchDragDestination(from: .layout(second.id)), .layout(second.id))
        XCTAssertEqual(projection.searchDragDestination(from: .layout(UUID())), .layout(first.id))
    }

    func testEmptyLibraryRetainsRecommendationAndHomePlaceholder() {
        let projection = LauncherPageProjection(layoutPages: [], recommendations: [])
        XCTAssertEqual(projection.ids, [.recommendations, .emptyHome])
        XCTAssertEqual(projection.homeIndex, 1)
        XCTAssertNil(projection.layoutPosition(for: .emptyHome, in: []))
    }

    func testTwentyFourRecommendationsFillSixColumnsAndFourRows() {
        XCTAssertEqual(RecommendationLayout.sixByFour.capacity, ApplicationRecommendationEngine.limit)
        for width in [1000.0, 1400.0, 2400.0] {
            let centers = (0..<24).map {
                RecommendationGridLayout.center(index: $0, width: width, margin: 100, top: 120, tileWidth: 132, tileHeight: 120)
            }
            XCTAssertEqual(Set(centers.map(\.x)).count, 6)
            XCTAssertEqual(Set(centers.map(\.y)).count, 4)
            for row in Dictionary(grouping: centers, by: \.y).values {
                XCTAssertEqual(row.count, 6)
            }
            XCTAssertEqual(centers[0].y, 120)
            XCTAssertEqual(centers[18].y, 576)
            XCTAssertEqual(centers[18].x, centers[0].x)
            XCTAssertEqual(centers[23].x, centers[5].x)
        }
    }

    func testSparseRecommendationsKeepLeftAlignedSlots() {
        let first = RecommendationGridLayout.center(index: 0, width: 1400, margin: 100, top: 120, tileWidth: 132, tileHeight: 120)
        let nextRow = RecommendationGridLayout.center(index: 6, width: 1400, margin: 100, top: 120, tileWidth: 132, tileHeight: 120)
        let lastRow = RecommendationGridLayout.center(index: 18, width: 1400, margin: 100, top: 120, tileWidth: 132, tileHeight: 120)
        XCTAssertEqual(first, CGPoint(x: 320, y: 120))
        XCTAssertEqual(nextRow.x, first.x)
        XCTAssertEqual(lastRow.x, first.x)
        // Ordinary pages retain their original seven-column, five-row geometry.
        XCTAssertEqual(LauncherGridLayout.x(index: 7, columns: 7, width: 1600, margin: 100), 200)
        XCTAssertEqual(LauncherGridLayout.y(index: 7, columns: 7, rows: 5, top: 220, bottom: 720), 345)
    }

    func testWideScreensDoNotStretchRecommendationSpacing() {
        for width in [1600.0, 2400.0, 3200.0] {
            let centers = (0..<24).map {
                RecommendationGridLayout.center(index: $0, width: width, margin: 100, top: 220, tileWidth: 180, tileHeight: 150)
            }
            XCTAssertEqual(centers[1].x - centers[0].x, 200)
            XCTAssertEqual(centers[6].y - centers[0].y, 182)
            XCTAssertEqual((centers[0].x + centers[5].x) / 2, width / 2)
            XCTAssertEqual(centers[23].y, 766)
        }
    }

    func testCompactGridFitsNarrowWidthWithoutChangingColumnCount() {
        let centers = (0..<6).map {
            RecommendationGridLayout.center(index: $0, width: 1000, margin: 100, top: 120, tileWidth: 132, tileHeight: 120)
        }
        XCTAssertGreaterThanOrEqual(centers[0].x - 66, 100)
        XCTAssertLessThanOrEqual(centers[5].x + 66, 900)
        XCTAssertGreaterThanOrEqual(centers[1].x - centers[0].x, 132)
    }

    func testSevenByFiveLayoutFillsThirtyFiveSlotsAndUsesSevenColumnNavigation() {
        let layout = RecommendationLayout.sevenByFive
        XCTAssertEqual(layout.capacity, 35)
        let centers = (0..<layout.capacity).map {
            RecommendationGridLayout.center(index: $0, width: 1800, margin: 100, top: 220,
                tileWidth: 180, tileHeight: 150, layout: layout)
        }
        XCTAssertEqual(Set(centers.map(\.x)).count, 7)
        XCTAssertEqual(Set(centers.map(\.y)).count, 5)
        XCTAssertEqual(centers[28].x, centers[0].x)
        XCTAssertEqual(centers[34].x, centers[6].x)
        XCTAssertEqual(centers[7].y - centers[0].y, 182)
        let items = (0..<35).map { app("\($0)") }
        let projection = LauncherPageProjection(layoutPages: [], recommendations: items)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[0].id,
            direction: .down, recommendationLayout: layout)?.itemID, items[7].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[34].id,
            direction: .up, recommendationLayout: layout)?.itemID, items[27].id)
        XCTAssertEqual(projection.movingSelection(on: .recommendations, selectedItemID: items[34].id,
            direction: .right, recommendationLayout: layout)?.itemID, items[34].id)
    }

    func testSnapshotCapacityFollowsSelectedLayoutAndCanShrinkAgain() {
        let items = (0..<40).map { app("\($0)", count: $0 + 1) }
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: items, excluding: [], dataIsReady: true, limit: RecommendationLayout.sevenByFive.capacity)
        let larger = snapshot.resolve(items: items, excluding: [])
        XCTAssertEqual(larger.count, 35)
        XCTAssertEqual(larger.map(\.bundleIdentifier), (5..<40).reversed().map { "\($0)" })
        snapshot.begin(items: items, excluding: [], dataIsReady: true, limit: RecommendationLayout.sixByFour.capacity)
        XCTAssertEqual(snapshot.resolve(items: items, excluding: []).map(\.id), Array(larger.prefix(24)).map(\.id))
        snapshot.begin(items: Array(items.prefix(3)), excluding: [], dataIsReady: true, limit: RecommendationLayout.sevenByFive.capacity)
        XCTAssertEqual(snapshot.resolve(items: items, excluding: []).count, 3)
    }

    func testUnknownBackupLayoutFallsBackToSixByFour() throws {
        let data = Data(#"{"recommendationsEnabled":false,"recommendationLayout":"9x9"}"#.utf8)
        let backup = try JSONDecoder().decode(RecommendationBackupPreferences.self, from: data)
        XCTAssertFalse(backup.recommendationsEnabled)
        XCTAssertEqual(backup.recommendationLayout, .sixByFour)
    }

    @MainActor
    func testLayoutPreferenceFallbackAndBackupRestore() throws {
        let suite = "KidoXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("invalid", forKey: RecommendationPreferences.layoutKey)
        let preferences = RecommendationPreferences(defaults: defaults)
        XCTAssertEqual(preferences.layout, .sixByFour)
        preferences.apply(.init(enabled: false, layout: .sevenByFive))
        XCTAssertEqual(preferences.backup.recommendationLayout, .sevenByFive)
        XCTAssertFalse(preferences.isEnabled)
        let reloaded = RecommendationPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.layout, .sevenByFive)
        reloaded.isEnabled = true
        XCTAssertEqual(reloaded.layout, .sevenByFive)
        reloaded.apply(.init())
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(RecommendationPreferences(defaults: defaults).layout, .sixByFour)
    }

    func testOldBackupDefaultsAndNewBackupRoundTrip() throws {
        let old = Data(#"{"showMenuBarIcon":true,"launchSort":"default"}"#.utf8)
        let decoded = try JSONDecoder().decode(RecommendationBackupPreferences.self, from: old)
        XCTAssertTrue(decoded.recommendationsEnabled)
        XCTAssertEqual(decoded.recommendationLayout, .sixByFour)
        XCTAssertTrue(decoded.recommendationExclusions.isEmpty)
        let preferences = RecommendationBackupPreferences(enabled: false, layout: .sevenByFive, exclusions: [.init(applicationKey: "app", displayName: "App")])
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(RecommendationBackupPreferences.self, from: data), preferences)
    }

    func testSharedBackupObjectKeepsLegacyFieldsAndIgnoresNewFieldsInOldReader() throws {
        struct Backup: Encodable {
            var legacy = true
            var recommendations = RecommendationBackupPreferences(enabled: false)
            enum CodingKeys: String, CodingKey { case legacy }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(legacy, forKey: .legacy)
                try recommendations.encode(to: encoder)
            }
        }
        struct OldReader: Decodable { let legacy: Bool }
        let data = try JSONEncoder().encode(Backup())
        XCTAssertTrue(try JSONDecoder().decode(OldReader.self, from: data).legacy)
        XCTAssertFalse(try JSONDecoder().decode(RecommendationBackupPreferences.self, from: data).recommendationsEnabled)
    }

    @MainActor
    func testPreferencesPersistExcludeRestoreAndDeduplicateWithoutChangingApp() throws {
        let suite = "KidoXTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = RecommendationPreferences(defaults: defaults)
        let item = app("original", count: 7)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.layout, .sixByFour)
        preferences.exclude(item); preferences.exclude(item)
        preferences.isEnabled = false
        preferences.layout = .sevenByFive
        let reloaded = RecommendationPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.exclusions.count, 1)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.layout, .sevenByFive)
        XCTAssertEqual(item.openCount, 7)
        XCTAssertFalse(item.isHidden)
        reloaded.restore("original")
        XCTAssertTrue(reloaded.exclusions.isEmpty)
        reloaded.apply(.init(exclusions: [.init(applicationKey: "a", displayName: "a"), .init(applicationKey: "a", displayName: "a")]))
        XCTAssertEqual(reloaded.exclusions.count, 1)
        XCTAssertEqual(reloaded.layout, .sixByFour)
        reloaded.restoreAll()
        XCTAssertTrue(RecommendationPreferences(defaults: defaults).exclusions.isEmpty)
    }

    func testRecommendationBrowsingDoesNotMutateLayoutOrStatistics() throws {
        let item = app("a", count: 9)
        let pages = [LaunchPage(sortIndex: 4, items: [item])]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(pages)
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [item], excluding: [], dataIsReady: true)
        let recommendations = snapshot.resolve(items: [item], excluding: [])
        _ = LauncherPageProjection(layoutPages: pages, recommendations: recommendations)
        _ = snapshot.resolve(items: [item], excluding: ["a"])
        XCTAssertEqual(try encoder.encode(pages), before)
    }

    func testThousandAppRankingPerformance() {
        let items = (0..<1000).map { app("app.\($0)", count: $0 % 30 + 1) }
        measure { _ = ApplicationRecommendationEngine.rankedKeys(in: items) }
    }

    func testPinnedUnusedAppsPrecedeRecommendationsAndDoNotDuplicate() {
        let unused = app("unused", count: 0), popular = app("popular", count: 9)
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [unused, popular, app("other")], excluding: [], dataIsReady: true)
        XCTAssertEqual(snapshot.resolve(items: [unused, popular, app("other")], excluding: [], pinnedKeys: ["unused", "popular", "unused"]).map(\.bundleIdentifier), ["unused", "popular", "other"])
    }

    func testPinnedItemsRespectHiddenParentsAndUnavailablePaths() {
        var folder = app("folder"); folder.kind = .folder; folder.isHidden = true
        let child = app("child", count: 0, parent: folder.id)
        let other = app("other", count: 0)
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: [folder, child, other], excluding: [], dataIsReady: true)
        XCTAssertTrue(snapshot.resolve(items: [folder, child, other], excluding: [], unavailable: ["other"], pinnedKeys: ["child", "other"]).isEmpty)
    }

    func testUnpinRejoinsFrozenRankingAndExclusionDoesNotBackfill() {
        let items = (1...40).map { app("app\($0)", count: $0) }
        var snapshot = ApplicationRecommendationSnapshot()
        snapshot.begin(items: items, excluding: [], dataIsReady: true, limit: 24)
        let pinned = snapshot.resolve(items: items, excluding: [], pinnedKeys: ["app1"])
        XCTAssertEqual(pinned.count, 24)
        XCTAssertEqual(pinned.first?.bundleIdentifier, "app1")
        XCTAssertEqual(snapshot.resolve(items: items, excluding: [], pinnedKeys: []).first?.bundleIdentifier, "app40")
        XCTAssertEqual(snapshot.resolve(items: items, excluding: ["app40"]).count, 23)
        XCTAssertEqual(snapshot.resolve(items: items, excluding: []).count, 23)
    }

    @MainActor func testPinPreferencesSurviveSmallerLayoutAndRoundTrip() throws {
        let name = "KidoXTests.pins.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = RecommendationPreferences(defaults: defaults)
        prefs.layout = .sevenByFive
        for i in 0..<35 { XCTAssertTrue(prefs.pin(app("pin\(i)", count: 0))) }
        XCTAssertFalse(prefs.pin(app("overflow")))
        prefs.layout = .sixByFour
        XCTAssertEqual(prefs.pins.count, 35)
        XCTAssertFalse(prefs.canPinMore)
        let encoded = try JSONEncoder().encode(prefs.backup)
        let backup = try JSONDecoder().decode(RecommendationBackupPreferences.self, from: encoded)
        prefs.apply(backup)
        XCTAssertEqual(prefs.pins.map(\.applicationKey), (0..<35).map { "pin\($0)" })
        prefs.layout = .sevenByFive
        XCTAssertEqual(prefs.pins.count, 35)
    }

    @MainActor func testPinClearsExclusionAndMoveDoesNotChangeApplications() {
        let name = "KidoXTests.pins.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = RecommendationPreferences(defaults: defaults)
        let a = app("a", count: 0), b = app("b")
        prefs.exclude(a)
        XCTAssertTrue(prefs.pin(a))
        XCTAssertFalse(prefs.excludedKeys.contains("a"))
        XCTAssertTrue(prefs.pin(b))
        prefs.movePin("b", before: "a")
        XCTAssertEqual(prefs.pins.map(\.id), ["b", "a"])
        prefs.exclude(a)
        XCTAssertTrue(prefs.exclusions.isEmpty)
        XCTAssertEqual(a.openCount, 0)
    }

    func testOldBackupHasNoPins() throws {
        let prefs = try JSONDecoder().decode(RecommendationBackupPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(prefs.pinnedApplications.isEmpty)
    }

    @MainActor func testCompactNavigationHasIndependentAnchorsAndFallsBack() {
        let navigation = CompactLauncherNavigation()
        let all = UUID(), frequent = UUID()
        navigation.anchors["all"] = all
        navigation.anchors["frequent"] = frequent
        navigation.select(.frequent)
        navigation.reconcile(hasFrequent: false)
        XCTAssertEqual(navigation.section, .all)
        XCTAssertEqual(navigation.anchors["all"], all)
        XCTAssertEqual(navigation.anchors["frequent"], frequent)
        XCTAssertNil(LauncherPresentationMode(rawValue: "unknown"))
    }

    func testCompactSwipeCommitsOnReleaseAndFollowsPageOrder() {
        var gesture = CompactLauncherSwipe()
        XCTAssertNil(gesture.consume(x: 12, y: 1, phase: .began, timestamp: 0).pageDelta)
        XCTAssertNil(gesture.consume(x: 55, y: 2, phase: .changed, timestamp: 0.1).pageDelta)
        let result = gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.2)
        XCTAssertEqual(result.pageDelta, -1)
        XCTAssertTrue(result.consumesEvent)
        XCTAssertEqual(CompactLauncherSection.all.moving(by: -1), .frequent)
        XCTAssertEqual(CompactLauncherSection.frequent.moving(by: 1), .all)
        XCTAssertEqual(CompactLauncherSection.all.moving(by: 1), .all)
        XCTAssertEqual(CompactLauncherSection.frequent.moving(by: -1), .frequent)
    }

    func testCompactVerticalScrollNeverTurnsIntoPaging() {
        var gesture = CompactLauncherSwipe()
        XCTAssertFalse(gesture.consume(x: 2, y: 20, phase: .began, timestamp: 0).consumesEvent)
        XCTAssertFalse(gesture.consume(x: 100, y: 3, phase: .changed, timestamp: 0.1).consumesEvent)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.2).pageDelta)
    }

    func testCompactSmallAndCancelledSwipesDoNotSwitch() {
        var gesture = CompactLauncherSwipe()
        _ = gesture.consume(x: 20, y: 0, phase: .began, timestamp: 0)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.1).pageDelta)
        _ = gesture.consume(x: 80, y: 0, phase: .began, timestamp: 1)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .cancelled, timestamp: 1.1).pageDelta)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 1.2).pageDelta)
    }

    func testCompactMomentumAndDuplicateEndCannotSwitchTwice() {
        var gesture = CompactLauncherSwipe()
        _ = gesture.consume(x: -60, y: 0, phase: .began, timestamp: 0)
        XCTAssertEqual(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.1).pageDelta, 1)
        XCTAssertNil(gesture.consume(x: 150, y: 0, phase: .changed, momentum: true, timestamp: 0.2).pageDelta)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.3).pageDelta)
        _ = gesture.consume(x: 60, y: 0, phase: .began, timestamp: 1)
        XCTAssertEqual(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 1.1).pageDelta, -1)
    }

    func testCompactUnphasedScrollSwitchesOncePerBurst() {
        var gesture = CompactLauncherSwipe()
        XCTAssertEqual(gesture.consume(x: -60, y: 0, phase: .unphased, timestamp: 0).pageDelta, 1)
        XCTAssertNil(gesture.consume(x: 160, y: 0, phase: .unphased, timestamp: 0.1).pageDelta)
        XCTAssertEqual(gesture.consume(x: 60, y: 0, phase: .unphased, timestamp: 0.5).pageDelta, -1)
    }

    func testCompactDiagonalScrollWithoutClearHorizontalIntentDoesNotSwitch() {
        var gesture = CompactLauncherSwipe()
        _ = gesture.consume(x: 60, y: 58, phase: .began, timestamp: 0)
        XCTAssertNil(gesture.consume(x: 0, y: 0, phase: .ended, timestamp: 0.1).pageDelta)
    }

}
