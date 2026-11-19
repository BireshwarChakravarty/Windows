import ApplicationServices
import CoreGraphics
import Foundation

struct RunningApp: Sendable {
    let pid: pid_t
    let id: String
    let name: String
}

struct SnapResult: Sendable {
    var outcomes: [Int: PlacementOutcome] = [:]
    var displayChanged = false
    /// Frames that windows had before this snap moved them, for Undo.
    var previousFrames: [UUID: CGRect] = [:]
    /// Where each window ended up, for diagnostics.
    var finalFrames: [Int: CGRect] = [:]

    var placed: Int { outcomes.values.filter { $0 == .placed }.count }
    var tooLarge: Int { outcomes.values.filter { $0 == .tooLarge }.count }
    var failed: Int { outcomes.values.filter { $0 == .failed }.count }
}

/// Finds windows on a display and moves them with the Accessibility API.
///
/// Apps apply frame changes at their own pace: a busy app can take longer than a quick timeout,
/// and apps in enhanced accessibility mode (Chrome and Electron apps once an assistive app talks to
/// them) animate the change. So every move waits for the window to settle before judging it, retries,
/// and turns enhanced mode off for the duration of the move.
actor WindowService {
    private struct LiveWindow {
        let pid: pid_t
        let element: AXUIElement
        let choice: WindowChoice
    }

    private struct VisibleWindow {
        let pid: pid_t
        let frame: CGRect
        let order: Int
    }

    private static let readTimeout: Float = 0.5
    private static let writeTimeout: Float = 1.5
    private static let enhancedUserInterface = "AXEnhancedUserInterface"

    private var tracked: [UUID: LiveWindow] = [:]

    // MARK: Scanning

    func scan(_ display: DisplayTarget, applications: [RunningApp]) -> [WindowChoice] {
        guard AXIsProcessTrusted(), display.isActive else {
            tracked = [:]
            return []
        }

        let visible = visibleWindows(on: display)
        let byProcess = Dictionary(grouping: visible, by: \.pid)
        let previousByApp = Dictionary(grouping: tracked.values) { $0.choice.reference.appID }
        var results: [(order: Int, window: LiveWindow)] = []

        for app in applications {
            guard var visibleForApp = byProcess[app.pid] else { continue }
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, Self.readTimeout)
            guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for element in elements {
                AXUIElementSetMessagingTimeout(element, Self.readTimeout)
                guard let frame = frame(of: element), display.bounds.contains(frame.center),
                      let index = visibleForApp.firstIndex(where: { $0.frame.isNear(frame, tolerance: 16) }),
                      isAdjustable(element) else { continue }

                let visibleWindow = visibleForApp.remove(at: index)
                let previous = previousByApp[app.id]?.first { CFEqual($0.element, element) }
                let reference = WindowReference(
                    sessionID: previous?.choice.id ?? UUID(), appID: app.id, appName: app.name,
                    title: attribute(element, kAXTitleAttribute) as? String ?? "",
                    accessibilityID: attribute(element, kAXIdentifierAttribute) as? String
                )
                let window = LiveWindow(pid: app.pid, element: element, choice: WindowChoice(reference: reference))
                results.append((visibleWindow.order, window))
            }
        }

        tracked = Dictionary(uniqueKeysWithValues: results.map { ($0.window.choice.id, $0.window) })
        return results.sorted { $0.order < $1.order }.map(\.window.choice)
    }

    // MARK: Snapping

    func snap(_ arrangement: Arrangement, matches: [Int: WindowChoice], to display: DisplayTarget,
              forceEnhancedUserInterface: Bool = false) async -> SnapResult {
        var result = SnapResult()
        let frames = arrangement.layout.frames(in: display.workArea)
        let assignments = matches.sorted { $0.key < $1.key }
            .compactMap { slot, choice -> (slot: Int, window: LiveWindow, target: CGRect)? in
                guard frames.indices.contains(slot), let window = tracked[choice.id] else { return nil }
                let target = frames[slot]
                guard target.width > 0, target.height > 0, display.workArea.contains(target) else { return nil }
                return (slot, window, target)
            }

        // Turn enhanced accessibility mode off once per app while its windows move.
        var restoreEnhanced: [pid_t: AXUIElement] = [:]
        for pid in Set(assignments.map(\.window.pid)) {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, Self.writeTimeout)
            if forceEnhancedUserInterface {
                AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanTrue)
            }
            if attribute(application, Self.enhancedUserInterface) as? Bool == true {
                AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanFalse)
                restoreEnhanced[pid] = application
            }
        }

        for assignment in assignments {
            guard AXIsProcessTrusted(), display.isActive else {
                result.displayChanged = !display.isActive
                break
            }
            let element = assignment.window.element
            AXUIElementSetMessagingTimeout(element, Self.writeTimeout)
            guard let original = frame(of: element), isAdjustable(element) else {
                result.outcomes[assignment.slot] = .failed
                continue
            }

            let (outcome, final) = await place(element, at: assignment.target, in: display.workArea)
            result.outcomes[assignment.slot] = outcome
            result.finalFrames[assignment.slot] = final
            if outcome != .failed || !(final?.isNear(original, tolerance: 2) ?? true) {
                result.previousFrames[assignment.window.choice.id] = original
            }
        }

        for application in restoreEnhanced.values {
            AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanTrue)
        }
        return result
    }

    /// Moves windows back to frames recorded by `snap`. Returns how many reached their old frame.
    func restore(_ previousFrames: [UUID: CGRect], on display: DisplayTarget) async -> Int {
        var restored = 0
        for (id, target) in previousFrames {
            guard AXIsProcessTrusted(), display.isActive, display.bounds.intersects(target),
                  let window = tracked[id], isAdjustable(window.element) else { continue }
            AXUIElementSetMessagingTimeout(window.element, Self.writeTimeout)
            let application = AXUIElementCreateApplication(window.pid)
            let enhanced = attribute(application, Self.enhancedUserInterface) as? Bool == true
            if enhanced { AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanFalse) }
            if await place(window.element, at: target, in: display.bounds).outcome != .failed { restored += 1 }
            if enhanced { AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanTrue) }
        }
        return restored
    }

    /// Current frame of a scanned window, for diagnostics.
    func currentFrame(of id: UUID) -> CGRect? {
        tracked[id].flatMap { frame(of: $0.element) }
    }

    /// Requests `target`, waits for the app to apply it, and retries a few times.
    private func place(_ element: AXUIElement, at target: CGRect, in area: CGRect) async -> (outcome: PlacementOutcome, frame: CGRect?) {
        var outcome = PlacementOutcome.failed
        var latest: CGRect?
        for _ in 0..<3 {
            setFrame(target, on: element)
            latest = await settledFrame(of: element, toward: target)
            guard let latest else { continue }
            outcome = Placement.evaluate(latest, target: target)
            if outcome == .placed { break }
            if outcome == .tooLarge {
                // The app enforces a minimum size: keep it at the slot, inside the work area.
                let clamped = Placement.clamped(latest.size, at: target, in: area)
                setPosition(clamped.origin, on: element)
                return (outcome, await settledFrame(of: element, toward: clamped))
            }
        }
        return (outcome, latest)
    }

    /// Polls a window's frame until it reaches the target or stops changing.
    private func settledFrame(of element: AXUIElement, toward target: CGRect) async -> CGRect? {
        var previous: CGRect?
        var stableReads = 0
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(40))
            guard let current = frame(of: element) else { continue }
            if Placement.evaluate(current, target: target) == .placed { return current }
            if let previous, current.isNear(previous, tolerance: 0.5) {
                stableReads += 1
                // Unchanged for about 0.2 seconds: the app has finished with this request.
                if stableReads >= 5 { return current }
            } else {
                stableReads = 0
            }
            previous = current
        }
        return frame(of: element)
    }

    // MARK: Accessibility helpers

    private func visibleWindows(on display: DisplayTarget) -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return info.enumerated().compactMap { order, item in
            guard (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let dictionary = item[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  display.bounds.contains(frame.center) else { return nil }
            return VisibleWindow(pid: owner.int32Value, frame: frame, order: order)
        }
    }

    private func isAdjustable(_ element: AXUIElement) -> Bool {
        guard attribute(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              attribute(element, kAXMinimizedAttribute) as? Bool != true,
              attribute(element, "AXFullScreen") as? Bool != true else { return false }

        var canMove: DarwinBoolean = false
        var canResize: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &canMove) == .success
            && AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &canResize) == .success
            && canMove.boolValue && canResize.boolValue
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func setFrame(_ frame: CGRect, on element: AXUIElement) {
        // Size first so the move is not clamped by the old size, then position, then size again
        // because some apps clamp the first resize against the window's old position.
        setSize(frame.size, on: element)
        setPosition(frame.origin, on: element)
        setSize(frame.size, on: element)
    }

    private func setPosition(_ origin: CGPoint, on element: AXUIElement) {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ size: CGSize, on element: AXUIElement) {
        var dimensions = size
        guard let value = AXValueCreate(.cgSize, &dimensions) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func isNear(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
