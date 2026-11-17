import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import MacSnapperCore

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
        #expect(frames.count == 4)
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
    let window = makeWindow(app: "Xcode", title: "MacSnapper")
    let entry = SavedArrangement(name: "Studio", arrangement: Arrangement(layout: .grid, slots: [2: window.reference]))
    let encoded = try JSONEncoder().encode(entry)
    #expect(try JSONDecoder().decode(SavedArrangement.self, from: encoded) == entry)
}

private func makeWindow(app: String, title: String, sessionID: UUID = UUID(), accessibilityID: String? = nil) -> WindowChoice {
    WindowChoice(reference: WindowReference(sessionID: sessionID, appID: app, appName: app, title: title,
                                           accessibilityID: accessibilityID))
}
