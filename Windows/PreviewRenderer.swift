import AppKit
import SwiftUI

/// Renders the real menu bar panel with example data to PNG files, then quits.
///
/// Run `Windows.app/Contents/MacOS/Windows --render-previews <directory>`. CI uses this to check the
/// design of each build without Accessibility access or an ultrawide display.
@MainActor
enum PreviewRenderer {
    static func renderIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(index + 1) else {
            return
        }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        Task { @MainActor in
            var failed = false
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for scene in scenes() {
                    try render(scene, to: directory.appendingPathComponent("\(scene.name).png"))
                }
            } catch {
                FileHandle.standardError.write(Data("Rendering previews failed: \(error)\n".utf8))
                failed = true
            }
            exit(failed ? 1 : 0)
        }
    }

    private struct Scene {
        let name: String
        let dark: Bool
        let showingSaved: Bool
        let model: AppModel
    }

    private static func window(_ appID: String, _ appName: String, _ title: String) -> WindowReference {
        WindowReference(sessionID: UUID(), appID: appID, appName: appName, title: title, accessibilityID: nil)
    }

    private static func scenes() -> [Scene] {
        let notes = window("com.apple.Notes", "Notes", "Project Notes")
        let xcode = window("com.apple.dt.Xcode", "Xcode", "Windows — MenuPanel.swift")
        let safari = window("com.apple.Safari", "Safari", "Developer Documentation")
        let terminal = window("com.apple.Terminal", "Terminal", "windows — zsh")
        let mail = window("com.apple.mail", "Mail", "Inbox")
        let calendar = window("com.apple.iCal", "Calendar", "Week of November 16")
        let four = [notes, xcode, safari, terminal]
        let saved = [
            SavedArrangement(name: "Development", arrangement: Arrangement(layout: .columns, slots: [0: notes, 1: xcode, 2: safari, 3: terminal])),
            SavedArrangement(name: "Design review", arrangement: Arrangement(layout: .center, slots: [0: mail, 1: safari, 2: calendar])),
            SavedArrangement(name: "Pairing", arrangement: Arrangement(layout: .halves, slots: [0: xcode, 1: terminal])),
        ]
        let snapped = AppModel.Message(text: "Snapped 4 windows.", success: true)
        return [
            Scene(name: "Arrange-Columns-Dark", dark: true, showingSaved: false,
                  model: .preview(layout: .columns, windows: four, message: snapped, canUndo: true)),
            Scene(name: "Arrange-Columns-Light", dark: false, showingSaved: false,
                  model: .preview(layout: .columns, windows: four)),
            Scene(name: "Arrange-Center-Dark", dark: true, showingSaved: false,
                  model: .preview(layout: .center, windows: [mail, safari, calendar])),
            Scene(name: "Arrange-Grid-Dark", dark: true, showingSaved: false,
                  model: .preview(layout: .grid, windows: four)),
            Scene(name: "Arrange-Focus-Light", dark: false, showingSaved: false,
                  model: .preview(layout: .focus, windows: four)),
            Scene(name: "Arrange-Empty-Dark", dark: true, showingSaved: false,
                  model: .preview(layout: .thirds, windows: [])),
            Scene(name: "Permission-Dark", dark: true, showingSaved: false,
                  model: .preview(layout: .columns, windows: four, trusted: false)),
            Scene(name: "Permission-Light", dark: false, showingSaved: false,
                  model: .preview(layout: .columns, windows: four, trusted: false)),
            Scene(name: "Saved-Dark", dark: true, showingSaved: true,
                  model: .preview(layout: .columns, windows: four, saved: saved)),
            Scene(name: "Saved-Light", dark: false, showingSaved: true,
                  model: .preview(layout: .columns, windows: four, saved: saved)),
        ]
    }

    private static func render(_ scene: Scene, to url: URL) throws {
        let appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
        let root = MenuPanel(model: scene.model, showingSaved: scene.showingSaved)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scene.dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }

        // Let SwiftUI finish layout and asynchronous work such as image loading.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
