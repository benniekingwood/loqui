import SwiftUI

/// The Spectrum palette from docs/brand: four bar colors on a near-black ground.
package enum LoquiBrand {
    package static let coral = Color(red: 1.0, green: 0.42, blue: 0.36) // #FF6B5B
    package static let amber = Color(red: 1.0, green: 0.71, blue: 0.28) // #FFB547
    package static let mint = Color(red: 0.24, green: 0.86, blue: 0.59) // #3DDC97
    package static let sky = Color(red: 0.35, green: 0.78, blue: 0.98) // #5AC8FA
    package static let ground = Color(red: 0.06, green: 0.08, blue: 0.10) // #0F1419

    package static let spectrum: [Color] = [coral, amber, mint, sky]
}
