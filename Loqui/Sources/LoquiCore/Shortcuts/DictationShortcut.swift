import Foundation

/// Any physical key Loqui can watch for dictation, identified by its virtual
/// key code. Modifier keys are watched through modifier transitions and keep
/// working as modifiers; any other key is taken over while it is the dictation
/// key, so holding it does not type.
package struct DictationKey: Hashable, Identifiable, Sendable {
    package let keyCode: UInt16
    package let displayName: String

    /// `name` is what the keyboard layout prints on a character key, captured
    /// when the key is recorded. Modifier and named keys ignore it.
    package init(keyCode: UInt16, name: String? = nil) {
        self.keyCode = keyCode
        displayName = Self.modifiers[keyCode]?.name
            ?? Self.namedKeys[keyCode]?.name
            ?? name.flatMap(Self.printableName)
            ?? Self.characterKeys[keyCode]
            ?? "Key \(keyCode)"
    }

    package var id: UInt16 { keyCode }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
    }

    package static let rightOption = DictationKey(keyCode: 0x3D)
    package static let leftOption = DictationKey(keyCode: 0x3A)
    package static let rightCommand = DictationKey(keyCode: 0x36)
    package static let leftCommand = DictationKey(keyCode: 0x37)
    package static let rightControl = DictationKey(keyCode: 0x3E)
    package static let leftControl = DictationKey(keyCode: 0x3B)
    package static let rightShift = DictationKey(keyCode: 0x3C)
    package static let leftShift = DictationKey(keyCode: 0x38)
    package static let function = DictationKey(keyCode: 0x3F)

    /// Whether macOS reports this key as a modifier transition rather than as
    /// key down and key up events.
    package var isModifier: Bool {
        Self.modifiers[keyCode] != nil
    }

    /// The glyph shown beside the name, for keys that have one.
    package var symbol: String? {
        Self.modifiers[keyCode]?.symbol ?? Self.namedKeys[keyCode]?.symbol
    }

    /// Takes raw `NSEvent.ModifierFlags` bits so this model stays free of AppKit.
    /// Always false for a key that is not a modifier.
    package func isDown(modifierFlags: UInt) -> Bool {
        guard let downMask = Self.modifiers[keyCode]?.downMask else { return false }
        return modifierFlags & downMask != 0
    }

    /// A captured name, unless it is blank or holds control or private-use
    /// characters, which is how AppKit reports keys without a printed label.
    private static func printableName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let printable = !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xE000 ... 0xF8FF).contains(scalar.value)
        }
        return printable ? trimmed.uppercased() : nil
    }

    /// Each modifier's device-dependent `NX_DEVICE*KEYMASK` bit, set only while
    /// that physical key is down, or the Function flag for the Fn (Globe) key.
    private static let modifiers: [UInt16: (name: String, symbol: String, downMask: UInt)] = [
        0x3D: ("Right Option", "⌥", 0x40),
        0x3A: ("Left Option", "⌥", 0x20),
        0x36: ("Right Command", "⌘", 0x10),
        0x37: ("Left Command", "⌘", 0x08),
        0x3E: ("Right Control", "⌃", 0x2000),
        0x3B: ("Left Control", "⌃", 0x01),
        0x3C: ("Right Shift", "⇧", 0x04),
        0x38: ("Left Shift", "⇧", 0x02),
        0x3F: ("Fn (Globe)", "🌐", 1 << 23), // NSEvent.ModifierFlags.function
    ]

    /// Keys whose name does not depend on the keyboard layout.
    private static let namedKeys: [UInt16: (name: String, symbol: String?)] = [
        0x31: ("Space", "␣"), 0x24: ("Return", "↩"), 0x4C: ("Enter", "⌤"), 0x30: ("Tab", "⇥"),
        0x33: ("Delete", "⌫"), 0x75: ("Forward Delete", "⌦"), 0x35: ("Escape", "⎋"),
        0x7B: ("Left Arrow", "←"), 0x7C: ("Right Arrow", "→"), 0x7D: ("Down Arrow", "↓"), 0x7E: ("Up Arrow", "↑"),
        0x73: ("Home", "↖"), 0x77: ("End", "↘"), 0x74: ("Page Up", "⇞"), 0x79: ("Page Down", "⇟"),
        0x72: ("Help", nil), 0x47: ("Clear", "⌧"),
        0x7A: ("F1", nil), 0x78: ("F2", nil), 0x63: ("F3", nil), 0x76: ("F4", nil),
        0x60: ("F5", nil), 0x61: ("F6", nil), 0x62: ("F7", nil), 0x64: ("F8", nil),
        0x65: ("F9", nil), 0x6D: ("F10", nil), 0x67: ("F11", nil), 0x6F: ("F12", nil),
        0x69: ("F13", nil), 0x6B: ("F14", nil), 0x71: ("F15", nil), 0x6A: ("F16", nil),
        0x40: ("F17", nil), 0x4F: ("F18", nil), 0x50: ("F19", nil), 0x5A: ("F20", nil),
        0x52: ("Keypad 0", nil), 0x53: ("Keypad 1", nil), 0x54: ("Keypad 2", nil), 0x55: ("Keypad 3", nil),
        0x56: ("Keypad 4", nil), 0x57: ("Keypad 5", nil), 0x58: ("Keypad 6", nil), 0x59: ("Keypad 7", nil),
        0x5B: ("Keypad 8", nil), 0x5C: ("Keypad 9", nil), 0x41: ("Keypad .", nil), 0x43: ("Keypad *", nil),
        0x45: ("Keypad +", nil), 0x4B: ("Keypad /", nil), 0x4E: ("Keypad -", nil), 0x51: ("Keypad =", nil),
    ]

    /// U.S. layout names for character keys, used when no name was captured.
    private static let characterKeys: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O",
        0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
    ]
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
    package static let keyCodeDefaultsKey = "LoquiDictationKeyCode"
    package static let keyNameDefaultsKey = "LoquiDictationKeyName"
    package static let doubleTapLocksDefaultsKey = "LoquiDoubleTapLocks"
    /// Where versions before any-key support saved one of four named keys.
    package static let legacyKeyDefaultsKey = "LoquiDictationKey"

    private static let legacyKeys: [String: DictationKey] = [
        "rightOption": .rightOption,
        "rightCommand": .rightCommand,
        "rightControl": .rightControl,
        "function": .function,
    ]

    private let defaultsSuiteName: String?

    package init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    package func load() -> DictationShortcut {
        let defaults = userDefaults
        let key = savedKey(in: defaults)
            ?? defaults.string(forKey: Self.legacyKeyDefaultsKey).flatMap { Self.legacyKeys[$0] }
            ?? DictationShortcut.default.key
        let doubleTapLocks = defaults.object(forKey: Self.doubleTapLocksDefaultsKey) as? Bool
            ?? DictationShortcut.default.doubleTapLocks
        return DictationShortcut(key: key, doubleTapLocks: doubleTapLocks)
    }

    package func save(_ shortcut: DictationShortcut) {
        let defaults = userDefaults
        defaults.set(Int(shortcut.key.keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(shortcut.key.displayName, forKey: Self.keyNameDefaultsKey)
        defaults.set(shortcut.doubleTapLocks, forKey: Self.doubleTapLocksDefaultsKey)
        defaults.removeObject(forKey: Self.legacyKeyDefaultsKey)
    }

    private func savedKey(in defaults: UserDefaults) -> DictationKey? {
        guard let keyCode = defaults.object(forKey: Self.keyCodeDefaultsKey) as? Int,
              let validKeyCode = UInt16(exactly: keyCode) else {
            return nil
        }
        return DictationKey(keyCode: validKeyCode, name: defaults.string(forKey: Self.keyNameDefaultsKey))
    }

    private var userDefaults: UserDefaults {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
