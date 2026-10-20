import AppKit
import LoquiCore

/// Loqui's menu bar icon: the Cursor Wave mark drawn as a template image so
/// macOS tints it for light and dark menu bars. Idle shows sound bars ending in
/// a text cursor; recording raises the bars and turns the cursor into a dot.
///
/// Geometry is authored on a 24-point grid (matching the brand canvas) and drawn
/// at 18 points, the standard menu bar extra height.
package enum MenuBarGlyph {
    package static let pointSize: CGFloat = 18

    package static let idle = makeImage(recording: false)
    package static let recording = makeImage(recording: true)

    package static func image(recording: Bool) -> NSImage {
        recording ? Self.recording : idle
    }

    private static func makeImage(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            let scale = pointSize / 24
            NSColor.black.set()

            func line(from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat), width: CGFloat) {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: start.0 * scale, y: start.1 * scale))
                path.line(to: NSPoint(x: end.0 * scale, y: end.1 * scale))
                path.lineWidth = width * scale
                path.lineCapStyle = .round
                path.stroke()
            }

            if recording {
                line(from: (3, 8), to: (3, 16), width: 2)
                line(from: (6.5, 4.5), to: (6.5, 19.5), width: 2)
                line(from: (10, 7), to: (10, 17), width: 2)
                let radius: CGFloat = 3.3
                NSBezierPath(ovalIn: NSRect(
                    x: (17.5 - radius) * scale, y: (12 - radius) * scale,
                    width: radius * 2 * scale, height: radius * 2 * scale
                )).fill()
            } else {
                line(from: (3, 10), to: (3, 14), width: 2)
                line(from: (6.5, 7), to: (6.5, 17), width: 2)
                line(from: (10, 9), to: (10, 15), width: 2)
                line(from: (17, 5), to: (17, 19), width: 1.8)
                line(from: (14.8, 5), to: (19.2, 5), width: 1.8)
                line(from: (14.8, 19), to: (19.2, 19), width: 1.8)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = recording ? "Recording" : "Loqui"
        return image
    }
}
