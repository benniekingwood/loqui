import AppKit
import Combine
import Foundation
import os
import LoquiCore

private let hotKeyLogger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "hotkey")

package enum DictationKeyPhase: Equatable, Sendable {
    case pressed
    case released
    /// Another key went down while the dictation key was held, so the press is
    /// part of a chord such as Control-C rather than a request to dictate.
    case interrupted
}

package enum RecordingIntent: Equatable, Sendable {
    case start
    case stop
}

package enum HotKeyInstallationError: Error, Equatable, Sendable {
    case monitorRegistrationFailed
}

package enum HotKeyAvailability: Equatable, Sendable {
    case unregistered
    case registered
    case monitorRegistrationFailed

    package var isRegistered: Bool {
        self == .registered
    }

    package var recoveryMessage: String? {
        switch self {
        case .registered:
            nil
        case .unregistered:
            "The dictation shortcut is not active. The menu button still works."
        case .monitorRegistrationFailed:
            "The dictation shortcut could not start. Enable Accessibility access, then retry."
        }
    }
}

@MainActor
package protocol GlobalHotKeyService: AnyObject {
    func install(
        key: DictationKey,
        action: @escaping @MainActor @Sendable (DictationKeyPhase) -> Void
    ) -> Result<Void, HotKeyInstallationError>

    func uninstall()
}

/// Delays the hold decision: a press only becomes a recording once the key has
/// stayed down long enough to rule out a tap.
@MainActor
package protocol HoldTimerScheduling: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

/// Converts global dictation-key transitions into two recording gestures.
/// Holding the key records for as long as it is held; two quick taps latch
/// recording on until the next press stops it, unless the user turned
/// hands-free mode off. A single tap does nothing, and a press that becomes a
/// chord with another key before the hold threshold is ignored, so a modifier
/// dictation key stays usable in ordinary shortcuts.
@MainActor
package final class HotKeyController: ObservableObject {
    @Published package private(set) var availability: HotKeyAvailability = .unregistered
    @Published package private(set) var shortcut: DictationShortcut

    private enum GestureState: Equatable {
        case idle
        case pendingHold(startedAt: TimeInterval)
        case awaitingSecondTap(deadline: TimeInterval)
        case holding
        case latched
        case ignoringUntilRelease
    }

    private let service: any GlobalHotKeyService
    private let holdTimer: any HoldTimerScheduling
    private let holdThreshold: TimeInterval
    private let doubleTapInterval: TimeInterval
    private let now: @MainActor @Sendable () -> TimeInterval
    private var action: (@MainActor @Sendable (RecordingIntent) -> Void)?
    private var state: GestureState = .idle
    private var keyIsDown = false
    private var registrationIdentifier = UUID()
    private var isSuspended = false
    private let store: DictationShortcutStore?

    package init(store: DictationShortcutStore = DictationShortcutStore()) {
        self.store = store
        shortcut = store.load()
        service = SystemDictationKeyService()
        holdTimer = SystemHoldTimer()
        holdThreshold = 0.25
        doubleTapInterval = max(0.25, NSEvent.doubleClickInterval)
        now = { ProcessInfo.processInfo.systemUptime }
    }

    package init(
        service: any GlobalHotKeyService,
        shortcut: DictationShortcut = .default,
        holdTimer: any HoldTimerScheduling = SystemHoldTimer(),
        holdThreshold: TimeInterval = 0.25,
        doubleTapInterval: TimeInterval = 0.35,
        now: @escaping @MainActor @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.service = service
        self.shortcut = shortcut
        store = nil
        self.holdTimer = holdTimer
        self.holdThreshold = max(0.05, holdThreshold)
        self.doubleTapInterval = max(0.1, doubleTapInterval)
        self.now = now
    }

    package func register(
        action: @escaping @MainActor @Sendable (RecordingIntent) -> Void
    ) {
        self.action = action
        installSavedAction()
    }

    package func retry() {
        guard action != nil else {
            availability = .unregistered
            return
        }

        installSavedAction()
    }

    package func unregister() {
        registrationIdentifier = UUID()
        service.uninstall()
        resetGesture()
        keyIsDown = false
        availability = .unregistered
        action = nil
    }

    /// Recorder failures and the maximum-duration limit can end a session
    /// without another dictation-key event. Reset so the next press starts
    /// normally.
    package func recordingSessionDidEnd() {
        resetGesture()
    }

    /// Saves a new shortcut and starts watching its key right away. A recording
    /// held or latched by the old key is stopped, because the old key's release
    /// can no longer reach the gesture.
    package func update(_ newShortcut: DictationShortcut) {
        guard newShortcut != shortcut else { return }
        let keyChanged = newShortcut.key != shortcut.key
        shortcut = newShortcut
        store?.save(newShortcut)
        if keyChanged {
            stopActiveGesture()
            if !isSuspended {
                installSavedAction()
            }
        }
    }

    /// Stops watching the dictation key while Settings records a new one, so
    /// pressing the current key there does not start a recording.
    package func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        stopActiveGesture()
        registrationIdentifier = UUID()
        service.uninstall()
        keyIsDown = false
    }

    package func resume() {
        guard isSuspended else { return }
        isSuspended = false
        installSavedAction()
    }

    private func stopActiveGesture() {
        switch state {
        case .holding, .latched:
            action?(.stop)
        case .idle, .pendingHold, .awaitingSecondTap, .ignoringUntilRelease:
            break
        }
        resetGesture()
    }

    private func installSavedAction() {
        guard action != nil else {
            availability = .unregistered
            return
        }
        guard !isSuspended else { return }

        service.uninstall()
        resetGesture()
        keyIsDown = false
        let identifier = UUID()
        registrationIdentifier = identifier
        let key = shortcut.key
        switch service.install(key: key, action: { [weak self] phase in
            guard let self, self.registrationIdentifier == identifier else { return }
            self.handle(phase, at: self.now())
        }) {
        case .success:
            availability = .registered
            hotKeyLogger.notice("Global dictation-key recording monitor registered; key: \(key.displayName, privacy: .public); key code: \(key.keyCode, privacy: .public)")
        case .failure(.monitorRegistrationFailed):
            availability = .monitorRegistrationFailed
            hotKeyLogger.error("Global dictation-key recording monitor registration failed; key: \(key.displayName, privacy: .public); key code: \(key.keyCode, privacy: .public)")
        }
    }

    private func handle(_ phase: DictationKeyPhase, at timestamp: TimeInterval) {
        if phase == .interrupted {
            handleInterruption()
            return
        }
        let isDown = phase == .pressed
        guard isDown != keyIsDown else { return }
        keyIsDown = isDown
        switch phase {
        case .pressed:
            handlePress(at: timestamp)
        case .released:
            handleRelease(at: timestamp)
        case .interrupted:
            break
        }
    }

    /// A chord before the hold threshold cancels the pending recording. Once a
    /// recording has started, other keys are left alone.
    private func handleInterruption() {
        guard keyIsDown, case .pendingHold = state else { return }
        holdTimer.cancel()
        state = .ignoringUntilRelease
    }

    private func handlePress(at timestamp: TimeInterval) {
        switch state {
        case .idle:
            beginPendingHold(at: timestamp)
        case .pendingHold, .holding, .ignoringUntilRelease:
            break
        case let .awaitingSecondTap(deadline):
            if timestamp <= deadline {
                state = .latched
                action?(.start)
            } else {
                beginPendingHold(at: timestamp)
            }
        case .latched:
            state = .ignoringUntilRelease
            action?(.stop)
        }
    }

    private func handleRelease(at timestamp: TimeInterval) {
        switch state {
        case .idle, .awaitingSecondTap, .latched:
            break
        case .pendingHold:
            holdTimer.cancel()
            state = shortcut.doubleTapLocks ? .awaitingSecondTap(deadline: timestamp + doubleTapInterval) : .idle
        case .holding:
            state = .idle
            action?(.stop)
        case .ignoringUntilRelease:
            state = .idle
        }
    }

    private func beginPendingHold(at timestamp: TimeInterval) {
        state = .pendingHold(startedAt: timestamp)
        holdTimer.schedule(after: holdThreshold) { [weak self] in
            self?.holdThresholdElapsed()
        }
    }

    private func holdThresholdElapsed() {
        guard case .pendingHold = state else {
            return
        }

        state = .holding
        action?(.start)
    }

    private func resetGesture() {
        holdTimer.cancel()
        state = .idle
    }
}

@MainActor
package final class SystemHoldTimer: HoldTimerScheduling {
    private var pendingWork: DispatchWorkItem?

    package func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                action()
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    package func cancel() {
        pendingWork?.cancel()
        pendingWork = nil
    }
}

@MainActor
package final class SystemDictationKeyService: GlobalHotKeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var callbackContext: DictationKeyMonitorContext?
    private var eventTap: DictationKeyEventTap?

    package func install(
        key: DictationKey,
        action: @escaping @MainActor @Sendable (DictationKeyPhase) -> Void
    ) -> Result<Void, HotKeyInstallationError> {
        uninstall()

        guard key.isModifier else {
            guard let eventTap = DictationKeyEventTap(context: DictationKeyTapContext(key: key, action: action)) else {
                return .failure(.monitorRegistrationFailed)
            }
            self.eventTap = eventTap
            return .success(())
        }

        let context = DictationKeyMonitorContext(key: key, action: action)
        guard let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown],
            handler: { event in
                context.handle(event)
            }
        ) else {
            return .failure(.monitorRegistrationFailed)
        }

        guard let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown],
            handler: { event in
                context.handle(event)
                return event
            }
        ) else {
            NSEvent.removeMonitor(globalMonitor)
            return .failure(.monitorRegistrationFailed)
        }

        self.globalMonitor = globalMonitor
        self.localMonitor = localMonitor
        callbackContext = context
        return .success(())
    }

    package func uninstall() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        callbackContext = nil
        eventTap?.invalidate()
        eventTap = nil
    }
}

/// Tracks a modifier dictation key from modifier transitions. The key is never
/// consumed, so it keeps working as a modifier everywhere.
package final class DictationKeyMonitorContext: @unchecked Sendable {
    private let lock = NSLock()
    private let key: DictationKey
    private let action: @MainActor @Sendable (DictationKeyPhase) -> Void
    private var keyIsDown = false
    private var interruptedThisPress = false

    package init(
        key: DictationKey = .rightOption,
        action: @escaping @MainActor @Sendable (DictationKeyPhase) -> Void
    ) {
        self.key = key
        self.action = action
    }

    func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            handleKeyDown(isRepeat: event.isARepeat)
        } else {
            handle(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        }
    }

    package func handle(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        // Other modifier events (including synthetic Command events used for
        // paste) need not preserve the device-dependent bit for this key.
        // Only the physical dictation key can change this gesture.
        guard keyCode == key.keyCode else { return }
        let keyIsDown = key.isDown(in: modifierFlags)
        let phase = lock.withLock { () -> DictationKeyPhase? in
            guard keyIsDown != self.keyIsDown else {
                return nil
            }
            self.keyIsDown = keyIsDown
            interruptedThisPress = false
            return keyIsDown ? .pressed : .released
        }
        send(phase)
    }

    /// Any key typed while the dictation key is down makes the press a chord.
    package func handleKeyDown(isRepeat: Bool = false) {
        guard !isRepeat else { return }
        let phase = lock.withLock { () -> DictationKeyPhase? in
            guard keyIsDown, !interruptedThisPress else { return nil }
            interruptedThisPress = true
            return .interrupted
        }
        send(phase)
    }

    private func send(_ phase: DictationKeyPhase?) {
        guard let phase else {
            return
        }

        DispatchQueue.main.async { [action] in
            action(phase)
        }
    }
}

package extension DictationKey {
    func isDown(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
        isDown(modifierFlags: modifierFlags.rawValue)
    }
}

/// Decides which key events a non-modifier dictation key's event tap consumes.
/// The key's own presses, releases, and auto-repeats are consumed so holding it
/// does not type into the focused app. Pressed together with Command, Control,
/// or Option it passes through untouched, so shortcuts that use the key keep
/// working, including the Command-V that Loqui posts to paste.
package final class DictationKeyTapContext: @unchecked Sendable {
    private enum KeyState {
        case up
        case held(interrupted: Bool)
        case passingThrough
    }

    private static let shortcutFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

    private let lock = NSLock()
    private let key: DictationKey
    private let action: @MainActor @Sendable (DictationKeyPhase) -> Void
    private var state = KeyState.up

    package init(key: DictationKey, action: @escaping @MainActor @Sendable (DictationKeyPhase) -> Void) {
        self.key = key
        self.action = action
    }

    /// Returns whether the event is consumed.
    package func handle(keyCode: UInt16, isKeyDown: Bool, isRepeat: Bool, flags: CGEventFlags) -> Bool {
        let (consumed, phase) = lock.withLock { () -> (Bool, DictationKeyPhase?) in
            guard keyCode == key.keyCode else {
                guard isKeyDown, !isRepeat, case .held(interrupted: false) = state else { return (false, nil) }
                state = .held(interrupted: true)
                return (false, .interrupted)
            }
            switch (state, isKeyDown) {
            case (.up, true):
                if isRepeat || !flags.isDisjoint(with: Self.shortcutFlags) {
                    state = .passingThrough
                    return (false, nil)
                }
                state = .held(interrupted: false)
                return (true, .pressed)
            case (.held, true):
                return (true, nil)
            case (.held, false):
                state = .up
                return (true, .released)
            case (.passingThrough, false):
                state = .up
                return (false, nil)
            case (.passingThrough, true), (.up, false):
                return (false, nil)
            }
        }
        if let phase {
            DispatchQueue.main.async { [action] in
                action(phase)
            }
        }
        return consumed
    }
}

/// A session event tap on the main run loop for a non-modifier dictation key.
/// Creating it fails without Accessibility access.
@MainActor
final class DictationKeyEventTap {
    private let box: TapBox
    private let source: CFRunLoopSource

    /// Owns the tap port so the C callback can re-enable a tap that macOS
    /// disabled after a slow callback.
    fileprivate final class TapBox: @unchecked Sendable {
        let context: DictationKeyTapContext
        var port: CFMachPort?

        init(context: DictationKeyTapContext) {
            self.context = context
        }
    }

    init?(context: DictationKeyTapContext) {
        let box = TapBox(context: context)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dictationKeyTapCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            return nil
        }
        box.port = port
        self.box = box
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func invalidate() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        if let port = box.port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        box.port = nil
    }
}

private func dictationKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<DictationKeyEventTap.TapBox>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let port = box.port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    case .keyDown, .keyUp:
        let consumed = box.context.handle(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            isKeyDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            flags: event.flags
        )
        return consumed ? nil : Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
