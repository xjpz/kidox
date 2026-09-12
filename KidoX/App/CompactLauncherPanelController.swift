import AppKit
import SwiftUI

extension Notification.Name {
    static let kidoXCompactLauncherRequested = Notification.Name("KidoXCompactLauncherRequested")
}

@MainActor
final class CompactLauncherPanelController {
    private let store: KidoXStore
    private let navigation = CompactLauncherNavigation()
    private let onExpand: () -> Void
    private let onSettings: (SettingsPane?) -> Void
    private var panel: KidoXPanel?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var origins: [String: NSPoint] = [:]
    private var screenKey = ""
    private var keepsPanelOpenForModalInteraction = false
    var isVisible: Bool { panel?.isVisible == true }

    init(store: KidoXStore, onExpand: @escaping () -> Void, onSettings: @escaping (SettingsPane?) -> Void) {
        self.store = store
        self.onExpand = onExpand
        self.onSettings = onSettings
    }

    func show(newSession: Bool = true) {
        if newSession {
            store.beginPresentationSession()
            navigation.folderID = nil
            navigation.selectedItemID = nil
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        screenKey = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
        let size = NSSize(width: min(920, max(320, visible.width - 48)), height: min(640, max(280, visible.height - 48)))
        var origin = origins[screenKey] ?? NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        store.searchFocusRequestID += 1
        installMonitors()
    }

    func hide() {
        if let panel, panel.isVisible { origins[screenKey] = panel.frame.origin }
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        // Release the view's search event monitor while preserving navigation in this owner.
        panel?.contentView = nil
        panel = nil
        keepsPanelOpenForModalInteraction = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        clickMonitor = nil
        localClickMonitor = nil
    }

    private func makePanel() -> KidoXPanel {
        let panel = KidoXPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("KidoX.compact")
        panel.title = "KidoX"
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = NSHostingView(rootView: CompactLauncherView(
            store: store, navigation: navigation,
            onDismiss: { [weak self] in self?.hide() },
            onExpand: { [weak self] in self?.onExpand() },
            onSettings: { [weak self] pane in self?.hide(); self?.onSettings(pane) },
            onModalInteractionChanged: { [weak self] active in self?.keepsPanelOpenForModalInteraction = active },
            onRestoreFocusAfterModalInteraction: { [weak self] in
                guard let panel = self?.panel, panel.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        ))
        // Keep the material at the AppKit window boundary. A SwiftUI mask around
        // a behind-window blur can flatten it into a gray, opaque-looking layer.
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 26
            glass.contentView = content
            panel.contentView = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 26
            material.layer?.masksToBounds = true
            content.autoresizingMask = [.width, .height]
            material.addSubview(content)
            panel.contentView = material
        }
        return panel
    }

    private func installMonitors() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible, !self.keepsPanelOpenForModalInteraction else { return }
                // Input-method candidate windows can extend beyond the panel.
                if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
                guard self.panel?.frame.contains(NSEvent.mouseLocation) == false else { return }
                self.hide()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.isVisible, !self.keepsPanelOpenForModalInteraction, let window = event.window, window !== self.panel,
               window.level == .normal, window.sheetParent == nil {
                self.hide()
            }
            return event
        }
    }
}
