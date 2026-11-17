import ApplicationServices
import CoreGraphics
import Foundation

struct RunningApp: Sendable {
    let pid: pid_t
    let id: String
    let name: String
}

struct SnapResult: Sendable {
    var placed: Set<Int> = []
    var constrained: Set<Int> = []
    var displayChanged = false
}

actor WindowService {
    private struct LiveWindow {
        let element: AXUIElement
        let choice: WindowChoice
    }

    private struct VisibleWindow {
        let pid: pid_t
        let frame: CGRect
        let order: Int
    }

    private var tracked: [UUID: LiveWindow] = [:]

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
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.2)
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
                let window = LiveWindow(element: element, choice: WindowChoice(reference: reference))
                results.append((visibleWindow.order, window))
            }
        }

        tracked = Dictionary(uniqueKeysWithValues: results.map { ($0.window.choice.id, $0.window) })
        return results.sorted { $0.order < $1.order }.map(\.window.choice)
    }

    func snap(_ arrangement: Arrangement, matches: [Int: WindowChoice], to display: DisplayTarget) -> SnapResult {
        var result = SnapResult()
        let frames = arrangement.layout.frames(in: display.workArea)

        for (slot, choice) in matches.sorted(by: { $0.key < $1.key }) {
            guard display.isActive else {
                result.displayChanged = true
                break
            }
            guard AXIsProcessTrusted(), frames.indices.contains(slot),
                  let element = tracked[choice.id]?.element,
                  let original = frame(of: element), display.bounds.contains(original.center),
                  isAdjustable(element) else { continue }

            let destination = frames[slot]
            guard destination.width > 0, destination.height > 0, display.workArea.contains(destination) else { continue }
            if original.isNear(destination, tolerance: 2) {
                result.placed.insert(slot)
                continue
            }

            setFrame(destination, on: element)
            if frame(of: element)?.isNear(destination, tolerance: 2) == true {
                result.placed.insert(slot)
            } else {
                if display.isActive,
                   let adjusted = frame(of: element), !adjusted.isNear(original, tolerance: 2) {
                    setFrame(original, on: element)
                }
                result.constrained.insert(slot)
            }
        }
        return result
    }

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
        var point = frame.origin
        var dimensions = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let size = AXValueCreate(.cgSize, &dimensions) else { return }

        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, size)
        // macOS can clamp the first move using the window's pre-resize frame.
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func isNear(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
