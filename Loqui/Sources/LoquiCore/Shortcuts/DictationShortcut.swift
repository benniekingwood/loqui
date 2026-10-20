import Foundation

/// Modifier keys Loqui can watch for dictation. Only keys that are rarely held
/// as part of ordinary chords are offered: the hold gesture sees modifier
/// transitions only, so a left-hand Command or Shift would start recordings
/// during everyday shortcuts and typing.
package enum DictationKey: String, CaseIterable, Identifiable, Sendable {
    case rightOption
    case rightCommand
    case rightControl
    case function

    package var id: String { rawValue }

    package init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else {
            return nil
        }
        self = key
    }

    package var keyCode: UInt16 {
        switch self {
        case .rightOption: 0x3D
        case .rightCommand: 0x36
        case .rightControl: 0x3E
        case .function: 0x3F
        }
    }

    /// The device-dependent `NX_DEVICER*KEYMASK` bit that is set only while this
    /// physical key is down, or the Function flag for the Fn (Globe) key.
    package var downMask: UInt {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        case .function: 1 << 23 // NSEvent.ModifierFlags.function
        }
    }

    package var displayName: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        case .function: "Fn (Globe)"
        }
    }

    package var symbol: String {
        switch self {
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .rightControl: "⌃"
        case .function: "🌐"
        }
    }

    /// Takes raw `NSEvent.ModifierFlags` bits so this model stays free of AppKit.
    package func isDown(modifierFlags: UInt) -> Bool {
        modifierFlags & downMask != 0
    }
}

/// The user's dictation shortcut: which key to hold, and whether a double tap
/// latches recording on for hands-free dictation.
package struct DictationShortcut: Equatable, Sendable {
    package var key: DictationKey
    package var doubleTapLocks: Bool

    package init(key: DictationKey, doubleTapLocks: Bool) {
        self.key = key
        self.doubleTapLocks = doubleTapLocks
    }

    package static let `default` = DictationShortcut(key: .rightOption, doubleTapLocks: true)

    package var readyHint: String {
        doubleTapLocks
            ? "Hold \(key.displayName) to record, double-tap to lock"
            : "Hold \(key.displayName) to record"
    }

    package var menuHint: String {
        doubleTapLocks
            ? "Hold \(key.displayName) to dictate · double-tap to lock"
            : "Hold \(key.displayName) to dictate"
    }

    package var retryHint: String {
        "Hold \(key.displayName) to try again."
    }

    package var recordingHint: String {
        "Recording… Release or tap \(key.displayName) to stop"
    }
}

/// Persists the dictation shortcut in user defaults. Unknown or missing values
/// fall back to the default so a bad write can never disable dictation.
package struct DictationShortcutStore: Sendable {
    package static let keyDefaultsKey = "LoquiDictationKey"
    package static let doubleTapLocksDefaultsKey = "LoquiDoubleTapLocks"

    private let defaultsSuiteName: String?

    package init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    package func load() -> DictationShortcut {
        let defaults = userDefaults
        let key = defaults.string(forKey: Self.keyDefaultsKey).flatMap(DictationKey.init(rawValue:))
            ?? DictationShortcut.default.key
        let doubleTapLocks = defaults.object(forKey: Self.doubleTapLocksDefaultsKey) as? Bool
            ?? DictationShortcut.default.doubleTapLocks
        return DictationShortcut(key: key, doubleTapLocks: doubleTapLocks)
    }

    package func save(_ shortcut: DictationShortcut) {
        let defaults = userDefaults
        defaults.set(shortcut.key.rawValue, forKey: Self.keyDefaultsKey)
        defaults.set(shortcut.doubleTapLocks, forKey: Self.doubleTapLocksDefaultsKey)
    }

    private var userDefaults: UserDefaults {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
