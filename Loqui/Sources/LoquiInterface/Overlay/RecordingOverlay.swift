import AppKit
import Combine
import SwiftUI
import LoquiAudio
import LoquiCore

/// What the floating indicator shows for each engine state. It appears as soon
/// as a recording is requested and stays until the text has been delivered.
package enum RecordingOverlayPhase: Equatable, Sendable {
    case hidden
    case arming
    case listening
    case processing

    /// `isDictating` separates an armed recording from the launch-time model
    /// load, which shares the engine's `.starting` state.
    package init(_ state: TranscriptionEngine.State, isDictating: Bool = true) {
        guard isDictating else {
            self = .hidden
            return
        }
        switch state {
        case .idle, .failed: self = .hidden
        case .requestingPermission, .starting: self = .arming
        case .recording: self = .listening
        case .stopping, .transcribing, .delivering: self = .processing
        }
    }
}

package enum RecordingOverlayPreference {
    package static let defaultsKey = "LoquiShowsRecordingOverlay"

    package static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

/// Decides when the indicator names the microphone: on the first dictation
/// since launch, when the input device changed since the last dictation, and
/// after a long quiet stretch, when the system default may have moved without
/// anyone noticing. Naming it every time would just be noise.
package struct InputDeviceAnnouncer {
    package static let quietInterval: TimeInterval = 30 * 60

    private var lastDeviceUID: String?
    private var lastDictation: Date?

    package init() {}

    package mutating func shouldAnnounce(deviceUID: String, at now: Date) -> Bool {
        defer {
            lastDeviceUID = deviceUID
            lastDictation = now
        }
        guard let lastDeviceUID, let lastDictation else { return true }
        return deviceUID != lastDeviceUID || now.timeIntervalSince(lastDictation) >= Self.quietInterval
    }
}

/// Rolling input levels for the bars. The newest level sits in the middle and
/// older ones move outward, so speech ripples symmetrically from the center.
@MainActor
package final class RecordingOverlayModel: ObservableObject {
    package static let barCount = 11

    @Published package var phase: RecordingOverlayPhase = .hidden
    /// The microphone named above the bars, or nil when no label shows.
    @Published package var inputDeviceName: String?
    @Published package private(set) var levels: [CGFloat] = Array(repeating: 0, count: RecordingOverlayModel.barCount)

    private var history: [CGFloat] = Array(repeating: 0, count: RecordingOverlayModel.barCount / 2 + 1)
    private var smoothed: CGFloat = 0

    /// Maps a linear peak (0...1) onto 0...1 across speech's useful range, -50 to
    /// -10 dBFS, so quiet speech still moves the bars and shouting tops out.
    package nonisolated static func normalizedLevel(amplitude: Float) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        return CGFloat(min(max((decibels + 50) / 40, 0), 1))
    }

    package func push(amplitude: Float) {
        let target = Self.normalizedLevel(amplitude: amplitude)
        // Rise quickly with the voice, fall back gently between words.
        smoothed = target > smoothed ? target : smoothed * 0.7 + target * 0.3
        history.insert(smoothed, at: 0)
        history.removeLast()
        let half = Self.barCount / 2
        levels = (0 ..< Self.barCount).map { index in
            let distance = abs(index - half)
            // Outer bars trail and shrink a little, giving the pill a rounded silhouette.
            return history[distance] * (1 - CGFloat(distance) * 0.06)
        }
    }

    package func reset() {
        history = Array(repeating: 0, count: history.count)
        smoothed = 0
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

/// The pill-shaped indicator: Spectrum bars on Loqui's dark ground.
package struct RecordingOverlayView: View {
    @ObservedObject package var model: RecordingOverlayModel

    private static let minimumBarHeight: CGFloat = 3
    private static let maximumBarHeight: CGFloat = 20

    package var body: some View {
        TimelineView(.animation(paused: model.phase != .processing && model.phase != .arming)) { context in
            bars(at: context.date.timeIntervalSinceReferenceDate)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(LoquiBrand.ground.opacity(0.94))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private func bars(at time: TimeInterval) -> some View {
        LinearGradient(colors: LoquiBrand.spectrum, startPoint: .leading, endPoint: .trailing)
            .mask {
                HStack(spacing: 3) {
                    ForEach(0 ..< RecordingOverlayModel.barCount, id: \.self) { index in
                        Capsule()
                            .frame(width: 3.5, height: barHeight(index: index, time: time))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: CGFloat(RecordingOverlayModel.barCount) * 6.5 - 3, height: Self.maximumBarHeight)
            .opacity(model.phase == .arming ? 0.55 + 0.25 * sin(time * 5) : 1)
            .animation(.linear(duration: 0.08), value: model.levels)
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let range = Self.maximumBarHeight - Self.minimumBarHeight
        switch model.phase {
        case .hidden, .arming:
            return Self.minimumBarHeight
        case .listening:
            return Self.minimumBarHeight + range * model.levels[index]
        case .processing:
            // A soft wave travels across the bars while Parakeet transcribes.
            let wave = (sin(time * 6 - Double(index) * 0.6) + 1) / 2
            return Self.minimumBarHeight + range * 0.45 * CGFloat(wave)
        }
    }

    private var accessibilityLabel: String {
        switch model.phase {
        case .hidden: ""
        case .arming: "Loqui is starting to listen"
        case .listening: "Loqui is listening"
        case .processing: "Loqui is transcribing"
        }
    }
}

/// The microphone's name in a small capsule above the bars.
struct InputDeviceLabel: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "mic.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(LoquiBrand.ground.opacity(0.94))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            )
            .frame(maxWidth: 320)
            .accessibilityLabel("Recording from \(name)")
    }
}

/// The bars, with the microphone's name above them while it is announced. The
/// bars stay pinned to the bottom so the label never moves them.
struct RecordingOverlayStack: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        VStack(spacing: 8) {
            if let name = model.inputDeviceName {
                InputDeviceLabel(name: name)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            RecordingOverlayView(model: model)
        }
        .animation(.easeOut(duration: 0.2), value: model.inputDeviceName)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Shows the indicator in a click-through panel above every app and Space,
/// centered just above the Dock on the screen the pointer is on.
@MainActor
package final class RecordingOverlayController {
    /// Wide and tall enough for the microphone label; the panel is transparent
    /// and click-through, so the spare room is invisible.
    private static let panelSize = NSSize(width: 360, height: 104)
    /// How long the microphone label stays once listening starts.
    package static let inputDeviceLabelDuration: Duration = .seconds(2)

    private let phases: AnyPublisher<RecordingOverlayPhase, Never>
    private let inputLevel: @MainActor () -> Float
    private let inputDevice: @MainActor () -> AudioInputDevice?
    let model = RecordingOverlayModel()
    private var announcer = InputDeviceAnnouncer()
    private var panel: NSPanel?
    private var stateObservation: AnyCancellable?
    private var levelTimer: Timer?
    private var labelDismissal: Task<Void, Never>?

    package convenience init(engine: TranscriptionEngine, inputDevices: any AudioInputResolving) {
        self.init(
            phases: engine.$state
                .combineLatest(engine.$isDictating)
                .map { RecordingOverlayPhase($0, isDictating: $1) }
                .eraseToAnyPublisher(),
            inputLevel: { [weak engine] in engine?.takeInputLevel() ?? 0 },
            inputDevice: { [weak inputDevices] in inputDevices?.resolveInputDevice() }
        )
    }

    package init(
        phases: AnyPublisher<RecordingOverlayPhase, Never>,
        inputLevel: @escaping @MainActor () -> Float,
        inputDevice: @escaping @MainActor () -> AudioInputDevice? = { nil }
    ) {
        self.phases = phases
        self.inputLevel = inputLevel
        self.inputDevice = inputDevice
    }

    package func start() {
        stateObservation = phases
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.apply(phase)
            }
    }

    package func stop() {
        stateObservation?.cancel()
        stateObservation = nil
        apply(.hidden)
    }

    private func apply(_ phase: RecordingOverlayPhase) {
        let visible = phase != .hidden && RecordingOverlayPreference.isEnabled()
        if phase == .listening {
            startLevelUpdates()
        } else {
            stopLevelUpdates()
        }
        if visible {
            if model.phase == .hidden {
                model.reset()
                announceInputDevice()
            }
            if phase == .listening {
                scheduleLabelDismissal()
            }
            model.phase = phase
            show()
        } else {
            model.phase = .hidden
            dismissLabel()
            hide()
        }
    }

    /// Names the microphone a new dictation is about to open, when the
    /// announcer says it is worth showing.
    private func announceInputDevice() {
        dismissLabel()
        guard let device = inputDevice(),
              announcer.shouldAnnounce(deviceUID: device.uid, at: .now) else { return }
        model.inputDeviceName = device.name
    }

    /// The label stays through arming and for a moment of listening, so it is
    /// still there when the speaker starts talking.
    private func scheduleLabelDismissal() {
        guard model.inputDeviceName != nil, labelDismissal == nil else { return }
        labelDismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.inputDeviceLabelDuration)
            guard !Task.isCancelled else { return }
            self?.model.inputDeviceName = nil
        }
    }

    private func dismissLabel() {
        labelDismissal?.cancel()
        labelDismissal = nil
        model.inputDeviceName = nil
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            position(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.phase == .hidden else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func position(_ panel: NSPanel) {
        guard let frame = FloatingPanel.frameAboveDock(size: Self.panelSize) else { return }
        panel.setFrame(frame, display: false)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        FloatingPanel.configure(panel)
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: RecordingOverlayStack(model: model))
        return panel
    }

    private func startLevelUpdates() {
        guard levelTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.push(amplitude: self.inputLevel())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
