import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How a window ended up after Windows tried to move it into a slot.
enum PlacementOutcome: String, Codable, Equatable, Sendable {
    /// The window sits in its slot.
    case placed
    /// The window is at its slot but the app keeps it larger than the slot (a minimum size).
    case tooLarge
    /// The window did not reach its slot, for example because the app did not respond.
    case failed
}

enum Placement {
    /// Classifies a window frame read back after a move.
    ///
    /// - Parameters:
    ///   - tolerance: Rounding allowed on every edge.
    ///   - slack: How much smaller than the slot a window may stay. Apps such as Terminal size
    ///     windows in whole character cells, so they stop a little short of the slot.
    static func evaluate(_ actual: CGRect, target: CGRect, tolerance: CGFloat = 2, slack: CGFloat = 40) -> PlacementOutcome {
        let originMatches = abs(actual.minX - target.minX) <= tolerance && abs(actual.minY - target.minY) <= tolerance
        let tooWide = actual.width > target.width + tolerance
        let tooTall = actual.height > target.height + tolerance
        let fillsSlot = actual.width >= target.width - slack && actual.height >= target.height - slack

        if originMatches, !tooWide, !tooTall, fillsSlot { return .placed }
        if originMatches, tooWide || tooTall { return .tooLarge }
        return .failed
    }

    /// The frame to request so a window with a minimum size stays inside the work area,
    /// anchored at its slot's top-left corner where possible.
    static func clamped(_ size: CGSize, at target: CGRect, in workArea: CGRect) -> CGRect {
        let x = min(target.minX, max(workArea.minX, workArea.maxX - size.width))
        let y = min(target.minY, max(workArea.minY, workArea.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
