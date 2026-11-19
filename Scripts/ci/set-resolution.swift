// Switches the main display of a CI Mac to its largest mode, so test windows have room.
import CoreGraphics
import Foundation

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
print("Available modes:", modes.map { "\($0.width)×\($0.height)" }.joined(separator: ", "))
guard let largest = modes.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
    print("No usable modes")
    exit(0)
}
var configuration: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&configuration)
CGConfigureDisplayWithDisplayMode(configuration, display, largest, nil)
let error = CGCompleteDisplayConfiguration(configuration, .forSession)
print("Display mode \(largest.width)×\(largest.height): \(error == .success ? "set" : "error \(error.rawValue)")")
