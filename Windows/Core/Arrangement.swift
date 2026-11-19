import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum Layout: String, CaseIterable, Codable, Identifiable, Sendable {
    case halves, thirds, center, columns, grid, focus

    var id: Self { self }

    var name: String {
        switch self {
        case .halves: "Halves"
        case .thirds: "Thirds"
        case .center: "Center"
        case .columns: "Columns"
        case .grid: "Grid"
        case .focus: "Focus"
        }
    }

    /// Unit rectangles with a top-left origin, in slot order.
    var zones: [CGRect] {
        switch self {
        case .halves:
            [CGRect(x: 0, y: 0, width: 0.5, height: 1),
             CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .thirds:
            (0..<3).map { CGRect(x: Double($0) / 3, y: 0, width: 1.0 / 3, height: 1) }
        case .center:
            [CGRect(x: 0, y: 0, width: 0.25, height: 1),
             CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
             CGRect(x: 0.75, y: 0, width: 0.25, height: 1)]
        case .columns:
            (0..<4).map { CGRect(x: Double($0) / 4, y: 0, width: 0.25, height: 1) }
        case .grid:
            [CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
             CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
             CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
             CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case .focus:
            [CGRect(x: 0, y: 0, width: 0.25, height: 0.5),
             CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
             CGRect(x: 0.75, y: 0, width: 0.25, height: 1),
             CGRect(x: 0, y: 0.5, width: 0.25, height: 0.5)]
        }
    }

    var slotCount: Int { zones.count }

    func frames(in workArea: CGRect, gap: CGFloat = 8) -> [CGRect] {
        zones.map { zone in
            // Outer edges get a full gap; shared edges split it so every gutter matches.
            let left = (workArea.minX + workArea.width * zone.minX).rounded()
                + (zone.minX < 0.001 ? gap : gap / 2)
            let top = (workArea.minY + workArea.height * zone.minY).rounded()
                + (zone.minY < 0.001 ? gap : gap / 2)
            let right = (workArea.minX + workArea.width * zone.maxX).rounded()
                - (zone.maxX > 0.999 ? gap : gap / 2)
            let bottom = (workArea.minY + workArea.height * zone.maxY).rounded()
                - (zone.maxY > 0.999 ? gap : gap / 2)
            return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
        }
    }
}

struct WindowReference: Codable, Equatable, Sendable {
    let sessionID: UUID
    let appID: String
    let appName: String
    let title: String
    let accessibilityID: String?
}

struct WindowChoice: Identifiable, Equatable, Sendable {
    let reference: WindowReference

    var id: UUID { reference.sessionID }
}

struct Arrangement: Codable, Equatable, Sendable {
    var layout: Layout = .columns
    var slots: [Int: WindowReference] = [:]

    /// Assignments for the slots the current layout shows. Others are kept so switching back restores them.
    var activeSlots: [Int: WindowReference] {
        slots.filter { layout.zones.indices.contains($0.key) }
    }

    func matches(in windows: [WindowChoice]) -> [Int: WindowChoice] {
        var matches: [Int: WindowChoice] = [:]
        var used: Set<UUID> = []
        let active = activeSlots
        let assignments = active.sorted { $0.key < $1.key }
        let windowsByApp = Dictionary(grouping: windows) { $0.reference.appID }
        let assignmentsByApp = Dictionary(grouping: active.values) { $0.appID }

        // Reserve live windows before falling back to persisted attributes.
        for phase in 0..<4 {
            for (slot, reference) in assignments where matches[slot] == nil {
                let candidates = windowsByApp[reference.appID, default: []]
                let appAssignments = assignmentsByApp[reference.appID, default: []]
                let matched: [WindowChoice]
                switch phase {
                case 0:
                    matched = candidates.filter { $0.id == reference.sessionID }
                case 1:
                    guard let identifier = reference.accessibilityID, !identifier.isEmpty,
                          appAssignments.filter({ $0.accessibilityID == identifier }).count == 1 else { continue }
                    matched = candidates.filter { $0.reference.accessibilityID == identifier }
                case 2:
                    guard !reference.title.isEmpty,
                          appAssignments.filter({ $0.title == reference.title }).count == 1 else { continue }
                    matched = candidates.filter { $0.reference.title == reference.title }
                default:
                    guard appAssignments.count == 1 else { continue }
                    matched = candidates
                }
                guard matched.count == 1, let window = matched.first, used.insert(window.id).inserted else {
                    continue
                }
                matches[slot] = window
            }
        }
        return matches
    }
}

struct SavedArrangement: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var arrangement: Arrangement
    var savedAt: Date

    init(name: String, arrangement: Arrangement) {
        id = UUID()
        self.name = name
        self.arrangement = arrangement
        savedAt = .now
    }
}
