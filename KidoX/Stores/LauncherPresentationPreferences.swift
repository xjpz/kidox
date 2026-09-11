import Foundation
import Observation

enum LauncherPresentationMode: String, Codable, CaseIterable {
    case fullscreen, compact
    static let storageKey = "KidoX.launcher.presentationMode"
    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .fullscreen
    }
}

enum CompactLauncherSection: String { case frequent, all }

@MainActor @Observable
final class CompactLauncherNavigation {
    var section: CompactLauncherSection = .all
    var folderID: UUID?
    var anchors: [String: UUID] = [:]
    var selectedItemID: UUID?

    func reconcile(hasFrequent: Bool) {
        if !hasFrequent && section == .frequent { section = .all }
    }

    func select(_ section: CompactLauncherSection) {
        self.section = section
        folderID = nil
        selectedItemID = nil
    }
}

/// One horizontal gesture changes at most one section. Vertical intent stays
/// locked for the entire gesture, including diagonal movement near its end.
struct CompactLauncherSwipe {
    enum Phase { case began, changed, ended, cancelled, unphased }
    struct Result {
        var consumesEvent = false
        var pageDelta: Int?
    }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x = 0.0
    private var y = 0.0
    private var lastTimestamp: Double?
    private var didSwitch = false
    private var isTracking = false

    mutating func reset() { self = Self() }

    mutating func consume(x dx: Double, y dy: Double, phase: Phase, momentum: Bool = false, timestamp: Double) -> Result {
        if momentum { return Result(consumesEvent: axis == .horizontal) }
        if phase == .began || (phase == .unphased && timestamp - (lastTimestamp ?? -.infinity) > 0.25) {
            reset()
        }
        lastTimestamp = timestamp
        if phase == .cancelled {
            let consumed = axis == .horizontal
            reset()
            return Result(consumesEvent: consumed)
        }
        if phase == .ended && !isTracking { return Result() }
        isTracking = true
        x += dx
        y += dy
        if axis == .undecided {
            if abs(y) >= 8 && abs(y) > abs(x) * 1.25 { axis = .vertical }
            else if abs(x) >= 8 && abs(x) > abs(y) * 1.25 { axis = .horizontal }
        }
        let consumes = axis == .horizontal || (axis == .undecided && abs(x) > abs(y))
        let commits = phase == .ended || phase == .unphased
        var result = Result(consumesEvent: consumes)
        if commits && axis == .horizontal && !didSwitch && abs(x) >= 48 {
            result.pageDelta = x > 0 ? -1 : 1
            didSwitch = true
        }
        if phase == .ended { isTracking = false }
        return result
    }
}

extension CompactLauncherSection {
    func moving(by delta: Int) -> Self {
        if delta < 0 && self == .all { return .frequent }
        if delta > 0 && self == .frequent { return .all }
        return self
    }
}
