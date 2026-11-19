import ApplicationServices
import CoreGraphics
import Foundation
import os

/// A plain-text record of what Windows did and why, kept at ~/Library/Logs/Windows/Windows.log.
///
/// Each snap writes the target and final frame of every window, every attempt, and any error an app
/// returned, so a window that does not land in its slot can be explained. Entries also go to the
/// unified log (subsystem: the bundle identifier, category "activity").
final class ActivityLog: @unchecked Sendable {
    static let shared = ActivityLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "Windows.ActivityLog")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Windows", category: "activity")
    private let formatter: ISO8601DateFormatter
    private let maximumBytes = 1_000_000

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let directory = library.appendingPathComponent("Logs/Windows", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("Windows.log")
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func write(_ message: String) {
        let date = Date()
        logger.info("\(message, privacy: .public)")
        queue.async { [self] in
            let line = "\(formatter.string(from: date))  \(message)\n"
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }

    /// The last `count` lines, for copying into a bug report.
    func recentLines(_ count: Int = 300) -> String {
        queue.sync {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
            return text.split(separator: "\n").suffix(count).joined(separator: "\n")
        }
    }

    func clear() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: rotatedURL)
        }
        write("Log cleared")
    }

    private var rotatedURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("1.log")
    }

    private func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int,
              size > maximumBytes else { return }
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }
}

extension CGRect {
    /// A compact frame for log lines, such as "x 8 y 33 w 1268 h 1399".
    var logText: String {
        String(format: "x %.0f y %.0f w %.0f h %.0f", minX, minY, width, height)
    }
}

extension AXError {
    /// A readable name for log lines.
    var logText: String {
        switch self {
        case .success: "ok"
        case .cannotComplete: "app did not respond in time"
        case .attributeUnsupported: "attribute unsupported"
        case .illegalArgument: "illegal argument"
        case .invalidUIElement: "window no longer exists"
        case .apiDisabled: "Accessibility access not granted"
        case .notImplemented: "not implemented by the app"
        case .failure: "failed"
        default: "error \(rawValue)"
        }
    }
}

extension String {
    /// Shortens window titles in log lines.
    func truncatedForLog(_ length: Int = 60) -> String {
        count > length ? String(prefix(length - 1)) + "…" : self
    }
}
