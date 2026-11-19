import AppKit

/// An end-to-end check of window snapping, used in CI on a real Mac:
///
///     Windows --snap-check <layout> --output <file> [--reverse] [--force-enhanced-ui]
///
/// It snaps the frontmost windows on the main display into `layout`, waits, reads every window's
/// frame back, and writes one line per slot plus PASS, FAIL or SKIP. `--reverse` assigns windows
/// back to front so each one has to move, and `--force-enhanced-ui` first puts the apps in enhanced
/// accessibility mode, which makes AppKit animate frame changes as it does for Chrome on many Macs.
@MainActor
enum SnapCheck {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--trust-check") {
            // Reports whether this exact copy of the app has Accessibility access, for CI.
            let trusted = AXIsProcessTrusted()
            let line = "\(trusted ? "TRUSTED" : "NOT TRUSTED") \(Bundle.main.bundlePath)"
            print(line)
            if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
                try? (line + "\n").write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
            }
            exit(trusted ? 0 : 1)
        }
        guard let index = arguments.firstIndex(of: "--snap-check"), arguments.indices.contains(index + 1),
              let layout = Layout(rawValue: arguments[index + 1]) else { return false }
        let output = arguments.firstIndex(of: "--output")
            .flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let reverse = arguments.contains("--reverse")
        let forceEnhanced = arguments.contains("--force-enhanced-ui")

        Task { @MainActor in
            var lines: [String] = []
            let status = await run(layout: layout, reverse: reverse, forceEnhanced: forceEnhanced) { line in
                lines.append(line)
                print(line)
            }
            if let output {
                try? (lines.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
            }
            exit(status)
        }
        return true
    }

    private static func run(layout: Layout, reverse: Bool, forceEnhanced: Bool,
                            log: (String) -> Void) async -> Int32 {
        guard AXIsProcessTrusted() else {
            log("SKIP: Accessibility access is not granted to this process")
            return 3
        }
        let displays = DisplayTarget.connected(includeBuiltIn: true)
        guard let display = displays.first(where: { $0.bounds.origin == .zero }) ?? displays.first else {
            log("FAIL: no display")
            return 2
        }
        log("Display \(display.name) \(display.resolution), work area \(display.workArea)")

        let service = WindowService()
        let windows = await service.scan(display, applications: RunningApp.visible())
        for window in windows {
            log("Found \(window.reference.appName): “\(window.reference.title)”")
        }
        guard windows.count >= layout.slotCount else {
            log("FAIL: \(layout.name) needs \(layout.slotCount) windows, found \(windows.count)")
            return 2
        }

        var chosen = Array(windows.prefix(layout.slotCount))
        if reverse { chosen.reverse() }
        var arrangement = Arrangement(layout: layout)
        var matches: [Int: WindowChoice] = [:]
        for (slot, window) in chosen.enumerated() {
            arrangement.slots[slot] = window.reference
            matches[slot] = window
        }

        let started = Date()
        let result = await service.snap(arrangement, matches: matches, to: display,
                                        forceEnhancedUserInterface: forceEnhanced)
        log(String(format: "Snap took %.2f s", Date().timeIntervalSince(started)))

        // Read back after a pause, so windows that drift or finish animating late are caught too.
        try? await Task.sleep(for: .seconds(1.5))
        let targets = layout.frames(in: display.workArea)
        var passed = true
        for (slot, window) in chosen.enumerated() {
            let final = await service.currentFrame(of: window.id)
            let settled = final.map { Placement.evaluate($0, target: targets[slot]) } ?? .failed
            let reported = result.outcomes[slot] ?? .failed
            log("Slot \(slot + 1) \(window.reference.appName): reported \(reported.rawValue), "
                + "after 1.5 s \(settled.rawValue); target \(targets[slot]), frame \(final.map { "\($0)" } ?? "none")")
            if reported != .placed || settled != .placed { passed = false }
        }
        log(passed ? "PASS" : "FAIL")
        return passed ? 0 : 1
    }
}
