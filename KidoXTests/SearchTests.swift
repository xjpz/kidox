import XCTest

final class SearchTests: XCTestCase {
    private func app(_ name: String, bundle: String? = nil, aliases: [LocalizedApplicationName]? = nil) -> LaunchItem {
        LaunchItem(kind: .application, displayName: name, subtitle: "", url: URL(fileURLWithPath: "/Applications/Example.app"),
                   bundleIdentifier: "com.example.app", bundleName: bundle, localizedSearchNames: aliases, sourcePath: "/Applications/Example.app")
    }
    private func entry(_ item: LaunchItem, language: String = "zh-Hans") -> ApplicationSearchIndex.Entry {
        .init(.init(item, language: language))
    }
    private func score(_ entry: ApplicationSearchIndex.Entry, _ query: String) -> Int? {
        entry.match(LaunchItemSearchQuery(query)!)?.score
    }

    func testSystemSettingsPinyinAndOriginalNames() {
        let settings = entry(app("系统设置", bundle: "System Settings"))
        for query in ["x", "xt", "xtsz", "xitong", "shezhi", "sz", "系统", "设置", "sys", "settings"] {
            XCTAssertNotNil(score(settings, query), query)
        }
        XCTAssertNil(score(entry(app("系统设置")), "t"))
        XCTAssertNil(score(settings, "xs"))
    }

    func testWeChatExactInitialsRankBeforeDeveloperTools() throws {
        let wechat = entry(app("微信", bundle: "WeChat"))
        let tools = entry(app("微信开发者工具", bundle: "wechatwebdevtools"))
        for query in ["wx", "weixin", "微信", "we", "wechat", "wc", "WX", "ｗｘ", "wei xin"] {
            XCTAssertNotNil(score(wechat, query), query)
        }
        XCTAssertLessThan(try XCTUnwrap(score(wechat, "wx")), try XCTUnwrap(score(tools, "wx")))
        XCTAssertNotNil(score(tools, "wxkf"))
        XCTAssertNotNil(score(tools, "wxkfzgj"))
        XCTAssertNil(score(wechat, "wxkf"))
        XCTAssertNil(score(wechat, "wei definitelymissing"))
    }

    func testPrefixPinyinAndSubstringRanking() throws {
        let xcode = entry(app("Xcode"))
        let settings = entry(app("系统设置", bundle: "System Settings"))
        let text = entry(app("文本编辑", bundle: "TextEdit"))
        XCTAssertLessThan(try XCTUnwrap(score(xcode, "x")), try XCTUnwrap(score(settings, "x")))
        XCTAssertLessThan(try XCTUnwrap(score(settings, "x")), try XCTUnwrap(score(text, "x")))
    }

    func testForeignAndLegacyAliasesDoNotPolluteShortQueries() {
        var preview = app("预览", bundle: "Preview", aliases: [.init(localeIdentifier: "vi", name: "Xem trước")])
        preview.localizedDisplayNames = ["Xem trước", "X", "微信"]
        let index = entry(preview)
        for query in ["x", "xe", "xt"] { XCTAssertNil(score(index, query), query) }
        for query in ["xem", "Xem trước", "微信", "yl", "yulan"] { XCTAssertNotNil(score(index, query), query) }
        XCTAssertNil(score(index, "wx")) // Unknown provenance must not be treated as Chinese.
    }

    func testChineseAliasesWorkInEnglishWithoutRomanizingJapaneseAliases() {
        let app = app("WeChat", aliases: [.init(localeIdentifier: "zh-Hans", name: "微信"), .init(localeIdentifier: "ja", name: "音楽")])
        XCTAssertNotNil(score(entry(app, language: "en"), "wx"))
        XCTAssertNil(score(entry(app, language: "en"), "yin"))
        let vietnamese = self.app("Preview", aliases: [.init(localeIdentifier: "vi", name: "Xem trước")])
        XCTAssertNotNil(score(entry(vietnamese, language: "vi-VN"), "x"))
        XCTAssertNil(score(entry(vietnamese, language: "en"), "x"))
    }

    func testMetadataRequiresThreeCharacters() {
        var item = app("Example"); item.bundleIdentifier = "com.tencent.xinWeChat"
        XCTAssertNil(score(entry(item), "xi"))
        XCTAssertNotNil(score(entry(item), "xin"))
    }

    func testSingleLetterPinyinNeverReceivesExactAbbreviationBonus() throws {
        let pinyin = try XCTUnwrap(score(entry(app("啊")), "a"))
        XCTAssertEqual(pinyin / 10_000, 3)
        XCTAssertLessThan(try XCTUnwrap(score(entry(app("Acorn")), "a")), pinyin)
    }

    func testMultiwordPenaltiesDoNotCrossNameSourcePriority() throws {
        let value = entry(app("a" + String(repeating: "b", count: 100)))
        let result = try XCTUnwrap(score(value, "a a"))
        XCTAssertEqual(result / 10_000, 2)
        XCTAssertEqual((result % 10_000) / 100, 1)
    }

    func testPhraseCorrectionsUmlautAndMixedNames() {
        XCTAssertNotNil(score(entry(app("音乐")), "yinyue"))
        XCTAssertNotNil(score(entry(app("音樂")), "yy"))
        XCTAssertNil(score(entry(app("音乐")), "yinle"))
        for query in ["lvse", "luse", "ls"] { XCTAssertNotNil(score(entry(app("绿色")), query), query) }
        let mixed = entry(app("微信 Mac 2"))
        for query in ["wxm2", "weixinmac2", "微信 mac", "mac 2"] { XCTAssertNotNil(score(mixed, query), query) }
        XCTAssertTrue(PinyinSearchNormalizer.forms(for: "Xcode").isEmpty)
        XCTAssertTrue(PinyinSearchNormalizer.forms(for: "微信", transform: { _ in nil }).isEmpty)
        let fallback = ApplicationSearchIndex.Entry(.init(app("微信"), language: "zh-Hans"), includePinyin: false)
        XCTAssertNotNil(score(fallback, "微信"))
    }

    func testCustomNameKeepsOriginalAndEnglishLookup() {
        var item = app("系统设置", bundle: "System Settings"); item.customDisplayName = "我的设置"
        for query in ["wdsz", "xtsz", "sys"] { XCTAssertNotNil(score(entry(item), query)) }
    }

    func testIndexUpdatesOnlySearchFieldsAndRejectsStaleWork() throws {
        var item = app("微信")
        var index = ApplicationSearchIndex()
        let first = try XCTUnwrap(index.prepare(items: [item], language: "zh-Hans"))
        XCTAssertNotNil(index.match(item: item, query: LaunchItemSearchQuery("微信")!))
        XCTAssertNil(index.match(item: item, query: LaunchItemSearchQuery("wx")!))
        XCTAssertTrue(index.apply(first.build(), generation: first.generation))
        item.openCount += 1; item.lastOpenedAt = Date(); item.sortIndex = 20; item.parentID = UUID()
        XCTAssertNil(index.prepare(items: [item], language: "zh-Hans"))
        item.customDisplayName = "聊天"
        let rename = try XCTUnwrap(index.prepare(items: [item], language: "zh-Hans"))
        XCTAssertEqual(rename.inputs.count, 1)
        XCTAssertFalse(index.apply(first.build(), generation: first.generation))
        XCTAssertTrue(index.apply(rename.build(), generation: rename.generation))
        XCTAssertNotNil(index.match(item: item, query: LaunchItemSearchQuery("lt")!))
        item.isHidden = true
        XCTAssertNil(index.match(item: item, query: LaunchItemSearchQuery("lt")!))
        item.isHidden = false
        XCTAssertNotNil(index.match(item: item, query: LaunchItemSearchQuery("lt")!))
        _ = index.prepare(items: [], language: "zh-Hans")
        XCTAssertTrue(index.entries.isEmpty)
        XCTAssertFalse(index.apply(rename.build(), generation: rename.generation))
    }

    func testIncrementalUpdateKeepsOtherEntriesAndPendingWork() throws {
        var a = app("微信"), b = app("系统设置")
        var index = ApplicationSearchIndex()
        let first = try XCTUnwrap(index.prepare(items: [a, b], language: "zh-Hans"))
        a.customDisplayName = "聊天"
        let next = try XCTUnwrap(index.prepare(items: [a, b], language: "zh-Hans"))
        XCTAssertEqual(next.inputs.count, 2) // B was still pending when A changed.
        XCTAssertFalse(index.apply(first.build(), generation: first.generation))
        XCTAssertTrue(index.apply(next.build(), generation: next.generation))
        b.customDisplayName = "设置中心"
        let single = try XCTUnwrap(index.prepare(items: [a, b], language: "zh-Hans"))
        XCTAssertEqual(single.inputs.map(\.id), [b.id])
        XCTAssertNotNil(index.match(item: a, query: LaunchItemSearchQuery("lt")!))
        let language = try XCTUnwrap(index.prepare(items: [a, b], language: "en"))
        XCTAssertEqual(language.inputs.count, 2)
        XCTAssertFalse(index.apply(single.build(), generation: single.generation))
    }

    func testOldRecordsDecodeAndNewAliasProvenanceRoundTrips() throws {
        let original = app("微信")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        old.removeValue(forKey: "localizedSearchNames")
        let decoded = try JSONDecoder().decode(LaunchItem.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.localizedSearchNames)
        var updated = decoded
        updated.localizedSearchNames = [.init(localeIdentifier: "zh-Hans", name: "微信")]
        let newData = try JSONEncoder().encode(updated)
        XCTAssertEqual(try JSONDecoder().decode(LaunchItem.self, from: newData), updated)
        struct OldReader: Decodable { let id: UUID; let displayName: String; let openCount: Int }
        XCTAssertEqual(try JSONDecoder().decode(OldReader.self, from: newData).id, original.id)
    }

    func testScannerPreservesLocaleProvenanceFromStringsAndLoctable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("app")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.searchfixture", "CFBundleName": "Preview", "CFBundlePackageType": "APPL", "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans", "vi"]]
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        for (locale, name) in [("zh-Hans", "预览"), ("vi", "Xem trước")] {
            let directory = resources.appendingPathComponent("\(locale).lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": name], format: .xml, options: 0)
                .write(to: directory.appendingPathComponent("InfoPlist.strings"))
        }
        try PropertyListSerialization.data(fromPropertyList: ["zh-Hant": ["CFBundleDisplayName": "預覽"]], format: .xml, options: 0)
            .write(to: resources.appendingPathComponent("InfoPlist.loctable"))
        let scanned = try XCTUnwrap(ApplicationScanner.makeApplicationItem(url: root))
        let aliases = try XCTUnwrap(scanned.localizedSearchNames)
        XCTAssertTrue(aliases.contains(.init(localeIdentifier: "zh-Hans", name: "预览")))
        XCTAssertTrue(aliases.contains(.init(localeIdentifier: "vi", name: "Xem trước")))
        XCTAssertTrue(aliases.contains(.init(localeIdentifier: "zh-Hant", name: "預覽")))
        XCTAssertNotNil(score(entry(scanned, language: "en"), "yl"))
        XCTAssertNil(score(entry(scanned, language: "zh-Hans"), "x"))
    }

    func testHotSearchPerformanceSeparatesColdBuildAndIncrementalUpdate() throws {
        let items = (0..<1000).map { app("微信工具\($0)", bundle: "Tool\($0)", aliases: [.init(localeIdentifier: "vi", name: "Xem trước \($0)")]) }
        var index = ApplicationSearchIndex()
        let coldStart = Date()
        let work = try XCTUnwrap(index.prepare(items: items, language: "zh-Hans"))
        index.apply(work.build(), generation: work.generation)
        print("Search cold index 1000: \(Date().timeIntervalSince(coldStart) * 1000) ms")
        let queries = ["wx", "weixin", "wxgj", "x", "tool", "missing", "wei xin"]
        var durations: [Double] = []
        for _ in 0..<3 {
            for raw in queries {
                let query = LaunchItemSearchQuery(raw)!
                let start = Date()
                let matches = items.compactMap { index.match(item: $0, query: query) }.sorted()
                durations.append(Date().timeIntervalSince(start) * 1000)
                if raw == "wx" { XCTAssertEqual(matches.count, 1000) }
            }
        }
        durations.sort()
        let p95 = durations[Int(ceil(Double(durations.count) * 0.95)) - 1]
        print("Search hot 1000 p95: \(p95) ms; samples: \(durations)")
        // Timing is reported in both configurations; the Release budget is checked on an idle run.
        var renamed = items; renamed[0].customDisplayName = "聊天"
        let updateStart = Date()
        let update = try XCTUnwrap(index.prepare(items: renamed, language: "zh-Hans"))
        XCTAssertEqual(update.inputs.count, 1)
        index.apply(update.build(), generation: update.generation)
        print("Search one-item update 1000: \(Date().timeIntervalSince(updateStart) * 1000) ms")
    }
}
