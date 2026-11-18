import AppKit
import SwiftUI

@main
@MainActor
struct WindowsApp: App {
    @State private var model = SnapperModel()

    var body: some Scene {
        MenuBarExtra {
            SnapperPanel(model: model)
        } label: {
            Image(nsImage: MenuMark.image)
                .accessibilityLabel("Windows")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum MenuMark {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // An ultrawide monitor split into four columns, matching the default layout.
            let bezel = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.25, width: 19.5, height: 9),
                                     xRadius: 2.2, yRadius: 2.2)
            bezel.lineWidth = 1.5
            bezel.stroke()

            for column in 0..<4 {
                let x = 3.25 + Double(column) * 4.125
                NSBezierPath(roundedRect: NSRect(x: x, y: 4.25, width: 3.125, height: 5),
                             xRadius: 0.6, yRadius: 0.6).fill()
            }

            NSRect(x: 10.25, y: 11.75, width: 1.5, height: 1.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 7.25, y: 13.25, width: 7.5, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Windows"
        return image
    }()
}
