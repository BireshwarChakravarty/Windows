import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class SnapperModel {
    struct Message: Equatable {
        let text: String
        var success = false
    }

    private struct Preferences: Codable {
        var displayKey: String?
        var draft = Arrangement()
        var saved: [SavedArrangement] = []
    }

    private enum Operation { case refresh, fill, snap, undo }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service = WindowService()
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var requestedAccess = false
    @ObservationIgnored private var isPreview = false
    private var undoFrames: [UUID: CGRect] = [:]
    private var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    private static let storageKey = "Windows.preferences.v1"
    private(set) var displays: [DisplayTarget] = []
    private(set) var windows: [WindowChoice] = []
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var busy = false
    private(set) var message: Message?

    var display: DisplayTarget? { displays.first { $0.key == preferences.displayKey } }
    var displayWasSelected: Bool { preferences.displayKey != nil }
    var arrangement: Arrangement { preferences.draft }
    var saved: [SavedArrangement] { preferences.saved }
    var matches: [Int: WindowChoice] { arrangement.matches(in: windows) }
    var assignedCount: Int { arrangement.activeSlots.count }
    var canSnap: Bool { trusted && display != nil && !busy && assignedCount > 0 }
    var canFill: Bool {
        trusted && display != nil && !busy && assignedCount < arrangement.layout.slotCount
            && windows.count > matches.count
    }
    var canUndo: Bool { trusted && display != nil && !busy && !undoFrames.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = stored
        } else {
            preferences = Preferences()
        }
    }

    func refresh() { run(.refresh) }
    func fill() { run(.fill) }
    func snap() { run(.snap) }
    func undo() { run(.undo) }

    func checkAccess() {
        if !isPreview, AXIsProcessTrusted() != trusted { refresh() }
    }

    func openAccessibility() {
        if !requestedAccess {
            requestedAccess = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func select(_ display: DisplayTarget) {
        guard !busy, preferences.displayKey != display.key else { return }
        preferences.displayKey = display.key
        message = nil
        undoFrames = [:]
        windows = []
        refresh()
    }

    func select(_ layout: Layout) {
        guard !busy, arrangement.layout != layout else { return }
        preferences.draft.layout = layout
        message = nil
    }

    func assign(_ window: WindowChoice, to slot: Int) {
        guard !busy, arrangement.layout.zones.indices.contains(slot), windows.contains(window) else { return }
        var draft = arrangement
        if let previous = matches.first(where: { $0.value.id == window.id })?.key, previous != slot {
            draft.slots[previous] = draft.slots[slot]
        }
        draft.slots[slot] = window.reference
        preferences.draft = draft
        message = nil
    }

    func clear(_ slot: Int) {
        guard !busy else { return }
        preferences.draft.slots.removeValue(forKey: slot)
        message = nil
    }

    func save(as name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !name.isEmpty, assignedCount > 0 else { return }
        let snapshot = Arrangement(layout: arrangement.layout, slots: arrangement.activeSlots)
        if let index = savedIndex(named: name) {
            var entry = saved[index]
            entry.name = name
            entry.arrangement = snapshot
            entry.savedAt = .now
            preferences.saved[index] = entry
        } else {
            preferences.saved.append(SavedArrangement(name: name, arrangement: snapshot))
        }
        message = Message(text: "Saved \(name).", success: true)
    }

    func hasSavedLayout(named name: String) -> Bool {
        savedIndex(named: name.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func savedIndex(named name: String) -> Int? {
        saved.firstIndex { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func restore(_ entry: SavedArrangement) {
        guard !busy else { return }
        preferences.draft = entry.arrangement
        message = nil
        if canSnap { snap() }
    }

    func delete(_ entry: SavedArrangement) {
        guard !busy else { return }
        preferences.saved.removeAll { $0.id == entry.id }
    }

    private func syncContext() {
        let previousDisplay = display
        trusted = AXIsProcessTrusted()
        displays = DisplayTarget.connected()

        if !displayWasSelected {
            let exact = displays.filter(\.isExactMatch)
            let wide = displays.filter(\.isUltrawide)
            if exact.count == 1 {
                preferences.displayKey = exact.first?.key
            } else if exact.isEmpty, wide.count == 1 {
                preferences.displayKey = wide.first?.key
            }
        }
        if !trusted || previousDisplay != display { windows = [] }
    }

    private func run(_ operation: Operation) {
        guard !isPreview else { return }
        syncContext()
        if busy {
            if operation == .refresh { refreshQueued = true }
            return
        }
        guard trusted, let target = display else { return }
        busy = true
        if operation != .refresh { message = nil }
        let applications = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            let pid = app.processIdentifier
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy != .prohibited, !app.isHidden else { return nil }
            let id = app.bundleIdentifier ?? app.executableURL?.path ?? "pid:\(pid)"
            return RunningApp(pid: pid, id: id, name: app.localizedName ?? id)
        }

        Task {
            defer {
                busy = false
                if refreshQueued {
                    refreshQueued = false
                    refresh()
                }
            }

            let found = await service.scan(target, applications: applications)
            syncContext()
            guard trusted, display == target else { return }
            windows = found

            var draft = arrangement
            let matches = draft.matches(in: found)
            for (slot, window) in matches { draft.slots[slot] = window.reference }
            if draft != arrangement { preferences.draft = draft }

            switch operation {
            case .refresh:
                break
            case .fill:
                let unassigned = draft.layout.zones.indices.filter { draft.slots[$0] == nil }
                let occupied = Set(matches.values.map(\.id))
                let available = found.filter { !occupied.contains($0.id) }
                for (slot, window) in zip(unassigned, available) { draft.slots[slot] = window.reference }
                preferences.draft = draft
                if available.isEmpty { message = Message(text: "Open windows on your external display, then refresh.") }
            case .snap:
                let result = await service.snap(draft, matches: matches, to: target)
                if !result.previousFrames.isEmpty { undoFrames = result.previousFrames }
                showResult(result, expected: draft.activeSlots.count)
            case .undo:
                let frames = undoFrames
                undoFrames = [:]
                let restored = await service.restore(frames, on: target)
                message = restored == frames.count
                    ? Message(text: restored == 1 ? "Moved 1 window back." : "Moved \(restored) windows back.", success: true)
                    : Message(text: "Moved \(restored) of \(frames.count) windows back. Others were closed or moved.")
            }
        }
    }

    /// A model with fixed example state for rendering previews. It never scans or moves windows.
    static func preview(layout: Layout, windows references: [WindowReference], saved: [SavedArrangement] = [],
                        message: Message? = nil, canUndo: Bool = false) -> SnapperModel {
        let suite = "Windows.preview"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = SnapperModel(defaults: defaults)
        model.isPreview = true
        model.trusted = true
        model.displays = [DisplayTarget(id: 0, key: "preview", name: "Ultrawide display", pixelsWide: 5120,
                                        pixelsHigh: 1440, bounds: .zero, workArea: .zero)]
        model.windows = references.map(WindowChoice.init(reference:))
        var draft = Arrangement(layout: layout)
        for (slot, reference) in references.prefix(layout.slotCount).enumerated() { draft.slots[slot] = reference }
        model.preferences = Preferences(displayKey: "preview", draft: draft, saved: saved)
        model.message = message
        if canUndo { model.undoFrames = [UUID(): .zero] }
        return model
    }

    private func showResult(_ result: SnapResult, expected: Int) {
        if result.displayChanged {
            message = Message(text: "The display changed. \(result.placed.count) of \(expected) windows snapped.")
        } else if result.placed.count == expected {
            message = Message(text: expected == 1 ? "Snapped 1 window." : "Snapped \(expected) windows.", success: true)
        } else if !result.constrained.isEmpty {
            message = Message(text: "\(result.placed.count) of \(expected) snapped. Some windows couldn’t fit their slots.")
        } else {
            message = Message(text: "\(result.placed.count) of \(expected) snapped. Reopen missing windows or choose replacements.")
        }
    }
}
