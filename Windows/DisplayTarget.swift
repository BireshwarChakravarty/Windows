import AppKit
import CoreGraphics

struct DisplayTarget: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let key: String
    let name: String
    let pixelsWide: Int
    let pixelsHigh: Int
    let bounds: CGRect
    let workArea: CGRect

    var isExactMatch: Bool { pixelsWide == 5120 && pixelsHigh == 1440 }
    var isUltrawide: Bool { bounds.width >= bounds.height * 3.4 }
    var resolution: String { "\(pixelsWide) × \(pixelsHigh)" }

    var isActive: Bool {
        CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
            && CGDisplayBounds(id) == bounds && Self.key(for: id) == key
    }

    @MainActor
    /// External displays in extended mode. `includeBuiltIn` also lists the built-in display, for checks.
    static func connected(includeBuiltIn: Bool = false) -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = identifier.uint32Value
            guard includeBuiltIn || CGDisplayIsBuiltin(id) == 0, CGDisplayIsInMirrorSet(id) == 0 else { return nil }

            // Accessibility and the WindowServer use the top-left corner as the origin.
            let bounds = CGDisplayBounds(id)
            let frame = screen.frame
            let visible = screen.visibleFrame
            let workArea = CGRect(x: bounds.minX + visible.minX - frame.minX,
                                  y: bounds.minY + frame.maxY - visible.maxY,
                                  width: visible.width, height: visible.height)
            let mode = CGDisplayCopyDisplayMode(id)
            return Self(id: id, key: key(for: id), name: screen.localizedName,
                        pixelsWide: mode?.pixelWidth ?? CGDisplayPixelsWide(id),
                        pixelsHigh: mode?.pixelHeight ?? CGDisplayPixelsHigh(id),
                        bounds: bounds, workArea: workArea)
        }
    }

    private static func key(for display: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "\(CGDisplayVendorNumber(display)):\(CGDisplayModelNumber(display)):\(CGDisplaySerialNumber(display)):\(display)"
    }
}
