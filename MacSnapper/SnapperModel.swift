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

    private enum Operation { case refresh, fill, snap }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service = WindowService()
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var requestedAccess = false
    private var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    private static let storageKey = "MacSnapper.preferences.v1"
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
    var canSnap: Bool { trusted && display != nil && !busy && !arrangement.slots.isEmpty }
    var canFill: Bool {
        trusted && display != nil && !busy && arrangement.slots.count < 4
            && windows.count > matches.count
    }

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

    func checkAccess() {
        if AXIsProcessTrusted() != trusted { refresh() }
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
        guard !busy, !name.isEmpty, !arrangement.slots.isEmpty else { return }
        if let index = savedIndex(named: name) {
            var entry = saved[index]
            entry.name = name
            entry.arrangement = arrangement
            entry.savedAt = .now
            preferences.saved[index] = entry
        } else {
            preferences.saved.append(SavedArrangement(name: name, arrangement: arrangement))
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
                showResult(result, expected: draft.slots.count)
            }
        }
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
