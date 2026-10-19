// Lists menu bar item windows (window layer 25) as tab-separated rows:
//   windowID  onscreen(0|1)  x  y  width  height  ownerPID  ownerName  windowName
// Coordinates are global points, the same space `screencapture -R` uses.
//
// No Accessibility or Screen Recording grant is needed for IDs and bounds.
// On macOS 26 every menu bar item window is owned by Control Center, so the
// owner cannot identify an app's item; driver.sh diffs window IDs across a
// launch instead.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowLayer as String] as? Int) == 25 {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func number(_ key: String) -> Int { Int((bounds[key] as? Double) ?? Double(bounds[key] as? Int ?? 0)) }
    let fields: [String] = [
        "\(window[kCGWindowNumber as String] as? Int ?? 0)",
        (window[kCGWindowIsOnscreen as String] as? Bool) == true ? "1" : "0",
        "\(number("X"))", "\(number("Y"))", "\(number("Width"))", "\(number("Height"))",
        "\(window[kCGWindowOwnerPID as String] as? Int ?? 0)",
        window[kCGWindowOwnerName as String] as? String ?? "",
        window[kCGWindowName as String] as? String ?? "",
    ]
    print(fields.joined(separator: "\t"))
}
