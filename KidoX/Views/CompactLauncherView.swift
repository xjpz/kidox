import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompactLauncherView: View {
    @Bindable var store: KidoXStore
    @Bindable var navigation: CompactLauncherNavigation
    let onDismiss: () -> Void
    let onExpand: () -> Void
    let onSettings: (SettingsPane?) -> Void
    @AppStorage(KidoXLaunchSort.storageKey) private var sortRaw = KidoXLaunchSort.default.rawValue
    @AppStorage(KidoXLanguage.storageKey) private var language = KidoXLanguage.system.rawValue
    @AppStorage("ClyAppLicense.status") private var licenseStatus = "Free"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused = false
    @State private var composing = false
    @State private var query = ""
    @State private var launching = false
    @State private var draggedPinID: UUID?
    @State private var pinDragOffset: CGSize = .zero
    @State private var tileFrames: [UUID: CGRect] = [:]

    private var sort: KidoXLaunchSort {
        let value = KidoXLaunchSort(rawValue: sortRaw) ?? .default
        return licenseStatus == "active" || !value.requiresPro ? value : .default
    }
    private var hasFrequent: Bool { store.recommendationPreferences.isEnabled && sort == .default }
    private var isFrequent: Bool { hasFrequent && navigation.section == .frequent && query.isEmpty && navigation.folderID == nil }
    private var contents: [LaunchItem] {
        if !query.isEmpty { return store.cachedSortedVisibleItems(sort: sort, query: query) }
        if let folder = navigation.folderID { return store.children(of: folder) }
        if isFrequent { return store.recommendationItems }
        if sort == .default { return store.pages.sorted { $0.sortIndex < $1.sortIndex }.flatMap(\.rootItems) }
        return store.cachedSortedVisibleItems(sort: sort, query: "")
    }
    private var context: String {
        if !query.isEmpty { return "search:\(query)" }
        if let folder = navigation.folderID { return folder.uuidString }
        return navigation.section.rawValue
    }
    private var scrollAnchor: Binding<UUID?> {
        let key = context
        return Binding(get: { navigation.anchors[key] }, set: { id in
            // Removing an old scroll view must not erase its remembered position.
            if let id { navigation.anchors[key] = id }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().padding(.horizontal, 20)
            if let folder = navigation.folderID, query.isEmpty {
                HStack {
                    Button { navigation.folderID = nil; navigation.selectedItemID = nil; focused = true } label: {
                        Image(systemName: "chevron.left").frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help(KidoXL10n.ui("Back"))
                    Text(store.items.first { $0.id == folder }?.effectiveDisplayName ?? "")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }.padding(.horizontal, 22).padding(.top, 6)
            }
            GeometryReader { geometry in
                let columns = isFrequent ? store.recommendationPreferences.layout.columns : max(1, min(7, Int((geometry.size.width - 36) / 108)))
                let cellHeight: CGFloat = isFrequent && store.recommendationPreferences.layout == .sevenByFive ? 99 : 124
                ZStack {
                    ScrollViewReader { reader in
                        ScrollView(.vertical) {
                            if contents.isEmpty {
                                emptyState.frame(maxWidth: .infinity).padding(.top, 125)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 0) {
                                    ForEach(contents) { item in
                                        tile(item, cellHeight: cellHeight)
                                            .id(item.id)
                                    }
                                }
                                .scrollTargetLayout()
                                .coordinateSpace(name: "compact.appGrid")
                                .onPreferenceChange(CompactTileFramesKey.self) { tileFrames = $0 }
                                .frame(maxWidth: isFrequent && columns == 6 ? 800 : .infinity)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
                                .background(CompactScrollPositionObserver(
                                    items: contents.map(\.id), columns: columns,
                                    rowHeight: cellHeight, anchor: scrollAnchor
                                ))
                            }
                        }
                        .onChange(of: navigation.selectedItemID) { _, id in
                            guard let id else { return }
                            navigation.anchors[context] = id
                            reader.scrollTo(id)
                        }
                        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                            let direction: SearchSelectionMove = press.key == .upArrow ? .up : press.key == .downArrow ? .down : press.key == .leftArrow ? .left : .right
                            return move(direction, columns: columns) ? .handled : .ignored
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(context)
                    // Each section has a fixed edge: the frequent page is left
                    // of all apps, for both insertion and removal.
                    .transition(reduceMotion ? .opacity : .move(edge: navigation.section == .frequent ? .leading : .trailing).combined(with: .opacity))
                }
                .clipped()
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2).padding(8)
            }
            if let feedback = store.recommendationPreferences.feedback {
                Text(KidoXL10n.ui(feedback)).font(.caption).foregroundStyle(.secondary).padding(8)
                    .task(id: feedback) {
                        try? await Task.sleep(for: .seconds(3))
                        if !Task.isCancelled { store.recommendationPreferences.feedback = nil }
                    }
            }
        }
        .background(CompactSwipeMonitor(
            isEnabled: hasFrequent && query.isEmpty && !composing && navigation.folderID == nil && draggedPinID == nil,
            onSwipe: { delta in
                let target = navigation.section.moving(by: delta)
                guard target != navigation.section else { return }
                selectSection(target)
            }
        ))
        .onAppear {
            query = store.searchQuery
            navigation.reconcile(hasFrequent: hasFrequent)
            if !query.isEmpty {
                navigation.selectedItemID = contents.first { $0.id == store.selectedItemID }?.id ?? contents.first?.id
            }
            focused = true
        }
        .onChange(of: store.searchFocusRequestID) { _, _ in focused = true }
        .onChange(of: navigation.selectedItemID) { _, id in store.selectedItemID = id }
        .onChange(of: store.searchQuery) { _, value in
            if !composing { applyQuery(value) }
        }
        .onChange(of: composing) { _, value in if !value { applyQuery(store.searchQuery) } }
        .onChange(of: hasFrequent) { _, _ in navigation.reconcile(hasFrequent: hasFrequent) }
        .onChange(of: contents.map(\.id)) { _, ids in
            if let selected = navigation.selectedItemID, !ids.contains(selected) { navigation.selectedItemID = nil }
            if !query.isEmpty && navigation.selectedItemID == nil { navigation.selectedItemID = ids.first }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kidoXPanelEscapeRequested)) { event in
            guard (event.object as? NSWindow)?.identifier?.rawValue == "KidoX.compact" else { return }
            escape()
        }
        .onKeyPress(.escape) { escape(); return .handled }
        .id(language)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("KidoX").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                .background(CompactPanelDragArea())
            if hasFrequent {
                HStack(spacing: 4) {
                    sectionButton(.frequent, symbol: "star.fill", title: "Frequent")
                    sectionButton(.all, symbol: "square.grid.2x2.fill", title: "All apps")
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    if store.searchQuery.isEmpty && !composing {
                        Text(KidoXL10n.ui("Search Applications")).foregroundStyle(.tertiary).allowsHitTesting(false)
                    }
                    SearchTextField(text: $store.searchQuery, isFocused: $focused, isComposing: $composing,
                        onEscape: escape,
                        onMoveSelection: { direction in move(direction, columns: currentColumns) },
                        onMovePage: { _ in false },
                        onCommit: { if let item = contents.first(where: { $0.id == navigation.selectedItemID }) ?? contents.first { open(item); return true }; return false },
                        textColor: .labelColor)
                        .frame(height: 24)
                }
                if !store.searchQuery.isEmpty {
                    Button { applyQuery(""); store.searchQuery = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(KidoXL10n.ui("Clear search"))
                }
            }
            .padding(.horizontal, 12).frame(maxWidth: 360).frame(height: 36)
            .background(.primary.opacity(0.035), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.7))
            Spacer(minLength: 8)
            Button(action: onExpand) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12)).frame(width: 28, height: 28) }
                .buttonStyle(.plain).help(KidoXL10n.ui("Full screen"))
            Menu {
                Button(KidoXL10n.ui("Open Settings")) { onSettings(nil) }
                Button(KidoXL10n.ui("Organize apps in full screen"), action: onExpand)
                Divider()
                ForEach(KidoXLaunchSort.allCases) { value in
                    Button(KidoXL10n.ui(value.title)) { sortRaw = value.rawValue }
                        .disabled(value.requiresPro && licenseStatus != "active")
                }
            } label: { Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(KidoXL10n.ui("Settings"))
            .accessibilityLabel(KidoXL10n.ui("Settings"))
        }
        .padding(.horizontal, 26).frame(height: 76)
        .background(CompactPanelDragArea())
    }

    private var currentColumns: Int {
        if isFrequent { return store.recommendationPreferences.layout.columns }
        let width = NSApp.windows.first { $0.identifier?.rawValue == "KidoX.compact" }?.frame.width ?? 920
        return max(1, min(7, Int((width - 36) / 108)))
    }

    private func sectionButton(_ section: CompactLauncherSection, symbol: String, title: String) -> some View {
        Button {
            guard !composing else { return }
            if query.isEmpty && navigation.folderID == nil {
                selectSection(section)
            } else {
                store.searchQuery = ""; query = ""
                navigation.select(section)
                focused = true
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                .foregroundStyle(navigation.section == section ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(navigation.section == section ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .padding(2)
        }
        .buttonStyle(.plain).help(KidoXL10n.ui(title))
        .accessibilityLabel(KidoXL10n.ui(title))
        .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
    }

    private func selectSection(_ section: CompactLauncherSection) {
        guard section != navigation.section else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.28)) {
            navigation.select(section)
        }
        focused = true
    }

    @ViewBuilder private var emptyState: some View {
        if store.isLoading { ProgressView() }
        else {
            VStack(spacing: 12) {
                Image(systemName: query.isEmpty ? "square.grid.2x2" : "magnifyingglass").font(.system(size: 26, weight: .light))
                Text(KidoXL10n.ui(query.isEmpty ? "No frequent apps yet" : "No apps found"))
            }.foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func tile(_ item: LaunchItem, cellHeight: CGFloat) -> some View {
        if isFrequent && store.recommendationPreferences.isPinned(item) {
            appButton(item, cellHeight: cellHeight)
                .offset(draggedPinID == item.id ? pinDragOffset : .zero)
                .zIndex(draggedPinID == item.id ? 1 : 0)
                .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("compact.appGrid"))
                    .onChanged { value in
                        draggedPinID = item.id
                        pinDragOffset = value.translation
                    }
                    .onEnded { value in
                        defer { draggedPinID = nil; pinDragOffset = .zero }
                        guard let target = contents.first(where: {
                            $0.id != item.id && tileFrames[$0.id]?.contains(value.location) == true
                        }) else { return }
                        let preferences = store.recommendationPreferences
                        preferences.movePin(ApplicationRecommendationEngine.key(for: item),
                            before: preferences.isPinned(target) ? ApplicationRecommendationEngine.key(for: target) : nil)
                    })
        } else {
            appButton(item, cellHeight: cellHeight)
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    guard isFrequent else { return false }
                    return acceptPinDrop(providers, before: nil)
                }
        }
    }

    private func appButton(_ item: LaunchItem, cellHeight: CGFloat) -> some View {
        Button { open(item) } label: {
            VStack(spacing: 8) {
                if item.kind == .folder {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(15), spacing: 3), count: 3), spacing: 3) {
                        ForEach(Array(store.children(of: item.id).prefix(9))) { child in
                            Image(nsImage: IconCache.icon(for: child.sourcePath)).resizable().frame(width: 15, height: 15)
                        }
                    }.padding(7).frame(width: 64, height: 64).background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(nsImage: IconCache.icon(for: item.sourcePath)).resizable().interpolation(.high).frame(width: 64, height: 64)
                }
                Text(item.effectiveDisplayName).font(.system(size: 14)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity).frame(height: cellHeight)
            .contentShape(Rectangle())
            .background(navigation.selectedItemID == item.id ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).help(item.effectiveDisplayName)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: CompactTileFramesKey.self,
                value: [item.id: geometry.frame(in: .named("compact.appGrid"))])
        })
        .accessibilityLabel(item.effectiveDisplayName)
        .accessibilityValue(store.recommendationPreferences.isPinned(item) ? KidoXL10n.ui("Pinned") : "")
        .contextMenu {
            Button(KidoXL10n.string(.open)) { open(item) }
            if item.kind == .application {
                PinApplicationMenu(item: item)
                if isFrequent && !store.recommendationPreferences.isPinned(item) {
                    Button(KidoXL10n.ui("Do not recommend this app")) { store.recommendationPreferences.exclude(item) }
                }
                Button(KidoXL10n.string(.showInFinder)) { store.revealInFinder(item) }
                Button(KidoXL10n.string(.hideApp)) { store.hideItem(item) }.disabled(licenseStatus != "active")
                if ApplicationUninstaller.canUninstallApplication(at: item.url) {
                    Button(KidoXL10n.string(.uninstallAppEllipsis)) { onSettings(.uninstaller) }
                }
            }
        }
    }

    private func applyQuery(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != query else { return }
        query = value
        navigation.selectedItemID = value.isEmpty ? nil : contents.first?.id
    }
    private func escape() {
        if !store.searchQuery.isEmpty { store.searchQuery = ""; applyQuery("") }
        else if navigation.folderID != nil { navigation.folderID = nil; navigation.selectedItemID = nil }
        else { onDismiss() }
    }
    private func move(_ direction: SearchSelectionMove, columns: Int) -> Bool {
        guard !contents.isEmpty else { return false }
        guard let index = contents.firstIndex(where: { $0.id == navigation.selectedItemID }) else {
            navigation.selectedItemID = contents.first?.id; return true
        }
        let delta = direction == .up ? -columns : direction == .down ? columns : direction == .left ? -1 : 1
        navigation.selectedItemID = contents[min(max(index + delta, 0), contents.count - 1)].id
        return true
    }
    private func open(_ item: LaunchItem) {
        if item.kind == .folder {
            navigation.folderID = item.id; navigation.selectedItemID = nil
            return
        }
        guard !launching else { return }
        launching = true
        store.errorMessage = nil
        store.open(item) { success in
            launching = false
            if success { onDismiss() }
        }
    }
}

private struct CompactTileFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Observe the native clip view because macOS 14 SwiftUI grid scroll-position
/// bindings can reset while switching content identities.
private struct CompactScrollPositionObserver: NSViewRepresentable {
    let items: [UUID]
    let columns: Int
    let rowHeight: CGFloat
    @Binding var anchor: UUID?

    func makeNSView(context: Context) -> ObserverView { ObserverView(configuration: self) }
    func updateNSView(_ view: ObserverView, context: Context) { view.configuration = self }

    final class ObserverView: NSView {
        var configuration: CompactScrollPositionObserver
        private weak var scrollView: NSScrollView?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        init(configuration: CompactScrollPositionObserver) {
            self.configuration = configuration
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            scrollView = nil
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil, observer == nil else { return }
            var ancestor = superview
            while let current = ancestor, !(current is NSScrollView) { ancestor = current.superview }
            guard let scroll = ancestor as? NSScrollView else { return }
            scrollView = scroll
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            if let id = configuration.anchor, let index = configuration.items.firstIndex(of: id) {
                let y = CGFloat(index / max(1, configuration.columns)) * configuration.rowHeight
                clip.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(clip)
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveAnchor() }
            }
        }

        private func saveAnchor() {
            guard let scrollView, !configuration.items.isEmpty else { return }
            let row = Int(max(0, scrollView.contentView.bounds.minY) / configuration.rowHeight)
            let index = min(row * max(1, configuration.columns), configuration.items.count - 1)
            configuration.anchor = configuration.items[index]
        }
    }
}

private struct CompactSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView(configuration: self) }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.configuration = self
        if !isEnabled { view.gesture.reset() }
    }

    final class MonitorView: NSView {
        var configuration: CompactSwipeMonitor
        var gesture = CompactLauncherSwipe()
        nonisolated(unsafe) private var monitor: Any?
        init(configuration: CompactSwipeMonitor) {
            self.configuration = configuration
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            gesture.reset()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.window?.isVisible == true, event.window === self.window else { return event }
                guard self.configuration.isEnabled, NSEvent.pressedMouseButtons == 0,
                      (self.window?.firstResponder as? NSTextView)?.hasMarkedText() != true else {
                    self.gesture.reset()
                    return event
                }
                let phase: CompactLauncherSwipe.Phase
                if event.phase.contains(.cancelled) { phase = .cancelled }
                else if event.phase.contains(.began) { phase = .began }
                else if event.phase.contains(.ended) { phase = .ended }
                else if event.phase.isEmpty { phase = .unphased }
                else { phase = .changed }
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
                let result = self.gesture.consume(x: event.scrollingDeltaX * scale, y: event.scrollingDeltaY * scale,
                    phase: phase, momentum: !event.momentumPhase.isEmpty, timestamp: event.timestamp)
                if let delta = result.pageDelta { self.configuration.onSwipe(delta) }
                return result.consumesEvent ? nil : event
            }
        }
    }
}

struct CompactPanelDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragArea { DragArea() }
    func updateNSView(_ view: DragArea, context: Context) {}
    final class DragArea: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
