import Foundation

/// The menu toggle writes this key through `@AppStorage`; players read it at
/// play time so a change applies to the very next recording.
package enum RecordingCuePreference {
    package static let defaultsKey = "LoquiPlaysRecordingCues"

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}
