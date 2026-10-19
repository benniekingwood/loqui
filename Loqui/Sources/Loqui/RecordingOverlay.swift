import AppKit
import Combine
import SwiftUI

/// What the floating indicator shows for each engine state. It appears as soon
/// as a recording is requested and stays until the text has been delivered.
enum RecordingOverlayPhase: Equatable, Sendable {
    case hidden
    case arming
    case listening
    case processing

    init(_ state: TranscriptionEngine.State) {
        switch state {
        case .idle, .failed: self = .hidden
        case .requestingPermission, .starting: self = .arming
        case .recording: self = .listening
        case .stopping, .transcribing, .delivering: self = .processing
        }
    }
}

enum RecordingOverlayPreference {
    static let defaultsKey = "LoquiShowsRecordingOverlay"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }
}

/// Rolling input levels for the bars. The newest level sits in the middle and
/// older ones move outward, so speech ripples symmetrically from the center.
@MainActor
final class RecordingOverlayModel: ObservableObject {
    static let barCount = 11

    @Published var phase: RecordingOverlayPhase = .hidden
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: RecordingOverlayModel.barCount)

    private var history: [CGFloat] = Array(repeating: 0, count: RecordingOverlayModel.barCount / 2 + 1)
    private var smoothed: CGFloat = 0

    /// Maps a linear peak (0...1) onto 0...1 across speech's useful range, -50 to
    /// -10 dBFS, so quiet speech still moves the bars and shouting tops out.
    nonisolated static func normalizedLevel(amplitude: Float) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        return CGFloat(min(max((decibels + 50) / 40, 0), 1))
    }

    func push(amplitude: Float) {
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

    func reset() {
        history = Array(repeating: 0, count: history.count)
        smoothed = 0
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

/// The pill-shaped indicator: Spectrum bars on Loqui's dark ground.
struct RecordingOverlayView: View {
    @ObservedObject var model: RecordingOverlayModel

    static let spectrum: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.36), // #FF6B5B
        Color(red: 1.0, green: 0.71, blue: 0.28), // #FFB547
        Color(red: 0.24, green: 0.86, blue: 0.59), // #3DDC97
        Color(red: 0.35, green: 0.78, blue: 0.98), // #5AC8FA
    ]
    private static let ground = Color(red: 0.06, green: 0.08, blue: 0.10) // #0F1419
    private static let minimumBarHeight: CGFloat = 3
    private static let maximumBarHeight: CGFloat = 20

    var body: some View {
        TimelineView(.animation(paused: model.phase != .processing && model.phase != .arming)) { context in
            bars(at: context.date.timeIntervalSinceReferenceDate)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(Self.ground.opacity(0.94))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private func bars(at time: TimeInterval) -> some View {
        LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing)
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

/// Shows the indicator in a click-through panel above every app and Space,
/// centered just above the Dock on the screen the pointer is on.
@MainActor
final class RecordingOverlayController {
    private static let panelSize = NSSize(width: 160, height: 64)
    private static let bottomMargin: CGFloat = 12

    private let states: AnyPublisher<TranscriptionEngine.State, Never>
    private let inputLevel: @MainActor () -> Float
    private let model = RecordingOverlayModel()
    private var panel: NSPanel?
    private var stateObservation: AnyCancellable?
    private var levelTimer: Timer?

    convenience init(engine: TranscriptionEngine) {
        self.init(
            states: engine.$state.eraseToAnyPublisher(),
            inputLevel: { [weak engine] in engine?.takeInputLevel() ?? 0 }
        )
    }

    init(
        states: AnyPublisher<TranscriptionEngine.State, Never>,
        inputLevel: @escaping @MainActor () -> Float
    ) {
        self.states = states
        self.inputLevel = inputLevel
    }

    func start() {
        stateObservation = states
            .removeDuplicates()
            .sink { [weak self] state in
                self?.apply(RecordingOverlayPhase(state))
            }
    }

    func stop() {
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
            }
            model.phase = phase
            show()
        } else {
            model.phase = .hidden
            hide()
        }
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
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - Self.panelSize.width / 2,
            y: visibleFrame.minY + Self.bottomMargin
        )
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let content = RecordingOverlayView(model: model)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        panel.contentView = NSHostingView(rootView: content)
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
