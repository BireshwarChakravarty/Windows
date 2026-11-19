import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import WindowsCore

@Test func fourColumnsUseTheUltrawideWorkArea() {
    let area = CGRect(x: -5120, y: 24, width: 5120, height: 1416)
    let frames = Layout.columns.frames(in: area)
    #expect(frames.count == 4)
    #expect(frames[0] == CGRect(x: -5112, y: 32, width: 1268, height: 1400))
    #expect(frames[3].maxX == -8)
    for (left, right) in zip(frames, frames.dropFirst()) {
        #expect(right.minX - left.maxX == 8)
    }
}

@Test func allLayoutsFitScaledAndVerticallyOffsetDisplays() {
    let area = CGRect(x: 104, y: -982, width: 3437, height: 944)
    for layout in Layout.allCases {
        let frames = layout.frames(in: area)
        #expect(frames.count == layout.slotCount)
        #expect((2...4).contains(frames.count))
        #expect(frames.allSatisfy { area.contains($0) && !$0.isEmpty })
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]))
            }
        }
    }
    let focus = Layout.focus.frames(in: area)
    #expect(focus[1].width > focus[0].width)
    #expect(focus[1].height > focus[0].height)
}

@Test func ultrawideSplitsKeepEvenGuttersAndEdges() {
    let area = CGRect(x: 0, y: 25, width: 5120, height: 1415)
    for layout in [Layout.halves, .thirds, .center] {
        let frames = layout.frames(in: area)
        #expect(frames.first?.minX == 8)
        #expect(frames.last?.maxX == 5112)
        #expect(frames.allSatisfy { $0.minY == 33 && $0.maxY == 1432 })
        for (left, right) in zip(frames, frames.dropFirst()) {
            #expect(right.minX - left.maxX == 8)
        }
    }
    let center = Layout.center.frames(in: area)
    #expect(center[1].width > center[0].width * 1.9)
    #expect(center[0].width == center[2].width)
}

@Test func switchingToFewerSlotsIgnoresButKeepsHiddenAssignments() {
    let editor = makeWindow(app: "Xcode", title: "Project")
    let browser = makeWindow(app: "Safari", title: "Docs")
    var arrangement = Arrangement(layout: .columns, slots: [0: editor.reference, 3: browser.reference])
    arrangement.layout = .halves
    #expect(arrangement.activeSlots.keys.sorted() == [0])
    #expect(arrangement.matches(in: [editor, browser]) == [0: editor])
    arrangement.layout = .columns
    #expect(arrangement.matches(in: [editor, browser]) == [0: editor, 3: browser])
}

@Test func savedLayoutsFromEarlierVersionsStillDecode() throws {
    let json = #"{"layout":"focus","slots":{}}"#
    let arrangement = try JSONDecoder().decode(Arrangement.self, from: Data(json.utf8))
    #expect(arrangement.layout == .focus)
}

@Test func matchingKeepsTrackedWindowsWhenTitlesChange() {
    let original = makeWindow(app: "Safari", title: "Original page")
    let renamed = makeWindow(app: "Safari", title: "New page", sessionID: original.id)
    let other = makeWindow(app: "Safari", title: "Original page")
    let arrangement = Arrangement(slots: [0: original.reference])
    #expect(arrangement.matches(in: [other, renamed])[0] == renamed)
}

@Test func matchingFindsReopenedWindowsByAppAndTitle() {
    let first = makeWindow(app: "Safari", title: "Documentation")
    let second = makeWindow(app: "Safari", title: "Dashboard")
    let reopenedFirst = makeWindow(app: "Safari", title: "Documentation")
    let reopenedSecond = makeWindow(app: "Safari", title: "Dashboard")
    let arrangement = Arrangement(slots: [0: first.reference, 2: second.reference])
    let matches = arrangement.matches(in: [reopenedSecond, reopenedFirst])
    #expect(matches == [0: reopenedFirst, 2: reopenedSecond])
}

@Test func matchingFallsBackToWindowIdentifierOrSingleWindow() {
    let editor = makeWindow(app: "Editor", title: "A", accessibilityID: "project")
    let reopenedEditor = makeWindow(app: "Editor", title: "B", accessibilityID: "project")
    let otherEditor = makeWindow(app: "Editor", title: "C")
    let terminal = makeWindow(app: "Terminal", title: "Old shell")
    let reopenedTerminal = makeWindow(app: "Terminal", title: "New shell")
    let arrangement = Arrangement(slots: [1: editor.reference, 3: terminal.reference])
    let matches = arrangement.matches(in: [otherEditor, reopenedEditor, reopenedTerminal])
    #expect(matches == [1: reopenedEditor, 3: reopenedTerminal])
}

@Test func matchingLeavesAmbiguousWindowsUnassignedAndNeverReusesAWindow() {
    let first = makeWindow(app: "Safari", title: "Untitled")
    let second = makeWindow(app: "Safari", title: "Untitled")
    let candidate = makeWindow(app: "Safari", title: "Untitled", sessionID: second.id)
    let duplicate = makeWindow(app: "Safari", title: "Untitled")
    let arrangement = Arrangement(slots: [0: first.reference, 3: second.reference])
    #expect(arrangement.matches(in: [candidate, duplicate]) == [3: candidate])
    #expect(arrangement.matches(in: [candidate]) == [3: candidate])
    #expect(arrangement.matches(in: [duplicate]).isEmpty)
}

@Test func savedArrangementRoundTrips() throws {
    let window = makeWindow(app: "Xcode", title: "Windows")
    let entry = SavedArrangement(name: "Studio", arrangement: Arrangement(layout: .grid, slots: [2: window.reference]))
    let encoded = try JSONEncoder().encode(entry)
    #expect(try JSONDecoder().decode(SavedArrangement.self, from: encoded) == entry)
}

private func makeWindow(app: String, title: String, sessionID: UUID = UUID(), accessibilityID: String? = nil) -> WindowChoice {
    WindowChoice(reference: WindowReference(sessionID: sessionID, appID: app, appName: app, title: title,
                                           accessibilityID: accessibilityID))
}

@Test func placementAcceptsExactAndCellSizedWindows() {
    let slot = CGRect(x: 8, y: 33, width: 1268, height: 1399)
    #expect(Placement.evaluate(slot, target: slot) == .placed)
    // Terminal-style windows stop short of the slot by part of a character cell.
    #expect(Placement.evaluate(CGRect(x: 8, y: 33, width: 1261, height: 1386), target: slot) == .placed)
    #expect(Placement.evaluate(CGRect(x: 9.5, y: 34, width: 1268, height: 1399), target: slot) == .placed)
}

@Test func placementReportsMinimumSizesAndWindowsThatDidNotMove() {
    let slot = CGRect(x: 8, y: 33, width: 470, height: 1040)
    #expect(Placement.evaluate(CGRect(x: 8, y: 33, width: 500, height: 1040), target: slot) == .tooLarge)
    // A window still at its old frame, or caught mid-animation, is not placed.
    #expect(Placement.evaluate(CGRect(x: 135, y: 195, width: 4700, height: 950), target: slot) == .failed)
    #expect(Placement.evaluate(CGRect(x: 60, y: 90, width: 900, height: 1040), target: slot) == .failed)
    // Moved but not resized yet.
    #expect(Placement.evaluate(CGRect(x: 8, y: 33, width: 300, height: 700), target: slot) == .failed)
}

@Test func clampingKeepsLargeWindowsOnScreen() {
    let area = CGRect(x: 0, y: 25, width: 1920, height: 1055)
    let lastColumn = CGRect(x: 1444, y: 33, width: 468, height: 1039)
    let frame = Placement.clamped(CGSize(width: 500, height: 1039), at: lastColumn, in: area)
    #expect(frame.maxX == 1920)
    #expect(frame.minY == 33)
    let firstColumn = CGRect(x: 8, y: 33, width: 468, height: 1039)
    #expect(Placement.clamped(CGSize(width: 500, height: 600), at: firstColumn, in: area).origin == firstColumn.origin)
}
