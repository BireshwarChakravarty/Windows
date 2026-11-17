import AppKit
import CoreGraphics
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

            let bezel = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1.5, width: 19.5, height: 10.25),
                                     xRadius: 2.2, yRadius: 2.2)
            bezel.lineWidth = 1.5
            bezel.stroke()

            for y in [3.75, 7.25] {
                for x in [3.75, 11.75] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 6.5, height: 2.5),
                                 xRadius: 0.65, yRadius: 0.65).fill()
                }
            }

            NSRect(x: 10.25, y: 11.5, width: 1.5, height: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 7.25, y: 13.25, width: 7.5, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Windows"
        return image
    }()
}
