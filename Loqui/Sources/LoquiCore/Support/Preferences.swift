import Foundation

/// The menu toggle writes this key through `@AppStorage`; players read it at
/// play time so a change applies to the very next recording.
package enum RecordingCuePreference {
    package static let defaultsKey = "LoquiPlaysRecordingCues"

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

/// Settings writes these keys through `@AppStorage`; the engine reads them when
/// a transcript arrives, so a change applies to the very next dictation.
package enum FillerWordPreference {
    package static let defaultsKey = "LoquiRemovesFillerWords"

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

package enum SpokenFormattingPreference {
    package static let defaultsKey = "LoquiAppliesSpokenFormatting"

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }
}
