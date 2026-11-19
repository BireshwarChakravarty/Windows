import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor
@Observable
final class AppModel {
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
    @ObservationIgnored private var accessWatcher: Task<Void, Never>?
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
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        ActivityLog.shared.write("Windows \(version) started on macOS \(ProcessInfo.processInfo.operatingSystemVersionString) "
            + "from \(appLocation); Accessibility \(trusted ? "allowed" : "not allowed")")
        if !trusted {
            watchForAccess()
            // Show the system prompt once per launch, which also adds Windows to the Accessibility list
            // ready to switch on. Skipped for the command-line checks CI runs.
            if !CommandLine.arguments.contains(where: { $0.hasPrefix("--") }) {
                requestedAccess = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    /// Shows a short confirmation in the panel.
    func showNotice(_ text: String) {
        message = Message(text: text, success: true)
    }

    func refresh() { run(.refresh) }
    func fill() { run(.fill) }
    func snap() { run(.snap) }
    func undo() { run(.undo) }

    func checkAccess() {
        if !isPreview, AXIsProcessTrusted() != trusted { refresh() }
    }

    // MARK: Accessibility permission

    /// macOS runs apps opened from a disk image or a quarantined download from a temporary, read-only
    /// location (App Translocation). Permission granted there doesn't stick, so the app must be moved.
    var needsMoveToApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }

    var appLocation: String {
        (Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath
    }

    func openAccessibility() {
        if !requestedAccess {
            requestedAccess = true
            // Adds Windows to the Accessibility list (switched off) and shows the system prompt.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        ActivityLog.shared.write("Opened Accessibility settings for \(appLocation)")
        watchForAccess()
    }

    /// Removes this app's Accessibility entry, which can be left over from an earlier build that macOS
    /// no longer matches, then adds it again so it can be switched on.
    func resetAccessibility() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", identifier]
        do {
            try process.run()
            process.waitUntilExit()
            ActivityLog.shared.write("Reset the Accessibility entry for \(identifier): exit \(process.terminationStatus)")
        } catch {
            ActivityLog.shared.write("Couldn’t reset the Accessibility entry: \(error.localizedDescription)")
        }
        requestedAccess = false
        message = Message(text: "Reset. Switch Windows on again in the list that opens.", success: true)
        openAccessibility()
    }

    /// Copies the app to /Applications, clears the download quarantine on the copy, and opens it.
    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications/Windows.app")
        let files = FileManager.default
        do {
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: source, to: destination)
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try? xattr.run()
            xattr.waitUntilExit()
            ActivityLog.shared.write("Moved Windows from \(appLocation) to /Applications; relaunching")
            relaunch(at: destination)
        } catch {
            ActivityLog.shared.write("Couldn’t move Windows to Applications: \(error.localizedDescription)")
            message = Message(text: "Couldn’t move Windows automatically. Drag it to Applications in Finder, then open it from there.")
        }
    }

    /// Opens a fresh copy of the app and quits this one. macOS sometimes only applies a newly granted
    /// Accessibility permission after a relaunch.
    func relaunch(at url: URL = Bundle.main.bundleURL) {
        ActivityLog.shared.write("Relaunching from \((url.path as NSString).abbreviatingWithTildeInPath)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Polls for the permission while it is missing, so the panel is ready even if it was closed
    /// while the person used System Settings.
    private func watchForAccess() {
        guard !isPreview, accessWatcher == nil else { return }
        accessWatcher = Task { [weak self] in
            for _ in 0..<600 {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.refresh()
                    break
                }
            }
            self?.accessWatcher = nil
        }
    }

    func select(_ display: DisplayTarget) {
        guard !busy, preferences.displayKey != display.key else { return }
        preferences.displayKey = display.key
        ActivityLog.shared.write("Selected display \(display.name) \(display.resolution)")
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
        ActivityLog.shared.write("Restoring saved layout “\(entry.name)” (\(entry.arrangement.layout.name))")
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
        let wasTrusted = trusted
        trusted = AXIsProcessTrusted()
        if trusted != wasTrusted {
            ActivityLog.shared.write("Accessibility access \(trusted ? "allowed" : "removed")")
        }
        let previousKeys = displays.map(\.key)
        displays = DisplayTarget.connected()
        if displays.map(\.key) != previousKeys {
            let list = displays.map { "\($0.name) \($0.resolution)" }.joined(separator: ", ")
            ActivityLog.shared.write("Displays: \(list.isEmpty ? "no external display" : list)")
        }

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
        let applications = RunningApp.visible()

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
                ActivityLog.shared.write("Snap requested: \(draft.layout.name), \(matches.count) of \(draft.activeSlots.count) assigned windows open")
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
                        message: Message? = nil, canUndo: Bool = false, trusted: Bool = true) -> AppModel {
        let suite = "Windows.preview"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(defaults: defaults)
        model.isPreview = true
        model.trusted = trusted
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
        let placed = result.placed
        if result.displayChanged {
            message = Message(text: "The display changed. \(placed) of \(expected) windows snapped.")
            return
        }
        if placed == expected {
            message = Message(text: expected == 1 ? "Snapped 1 window." : "Snapped \(expected) windows.", success: true)
            return
        }
        func count(_ number: Int) -> String { number == 1 ? "1 window" : "\(number) windows" }
        var problems: [String] = []
        if result.tooLarge > 0 { problems.append("\(count(result.tooLarge)) can’t shrink to fit") }
        if result.failed > 0 { problems.append("\(count(result.failed)) didn’t respond, so try Snap again") }
        let missing = expected - result.outcomes.count
        if missing > 0 { problems.append("\(count(missing)) not open") }
        message = Message(text: "\(placed) of \(expected) snapped. " + problems.joined(separator: "; ")
            + ". Details are in the activity log.")
    }
}

extension RunningApp {
    /// Apps that can own windows on screen, excluding Windows itself.
    @MainActor
    static func visible() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            let pid = app.processIdentifier
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy != .prohibited, !app.isHidden else { return nil }
            let id = app.bundleIdentifier ?? app.executableURL?.path ?? "pid:\(pid)"
            return RunningApp(pid: pid, id: id, name: app.localizedName ?? id)
        }
    }
}
