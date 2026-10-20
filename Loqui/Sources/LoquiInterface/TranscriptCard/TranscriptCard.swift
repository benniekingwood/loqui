import AppKit
import Combine
import SwiftUI
import LoquiCore

/// Drives one card: the transcript, the auto-dismiss countdown (paused while
/// the pointer is over the card), and the Copy confirmation.
@MainActor
package final class TranscriptCardModel: ObservableObject {
    package static let lifetime: TimeInterval = 15

    @Published package private(set) var transcript: UnplacedTranscript?
    @Published package private(set) var remainingFraction: Double = 1
    @Published package private(set) var copied = false
    @Published package var isHovering = false

    private var remaining: TimeInterval = TranscriptCardModel.lifetime

    package func present(_ transcript: UnplacedTranscript) {
        self.transcript = transcript
        remaining = Self.lifetime
        remainingFraction = 1
        copied = false
        isHovering = false
    }

    /// Advances the countdown and returns whether the card should now close.
    package func tick(elapsed: TimeInterval) -> Bool {
        guard transcript != nil, !isHovering, !copied else { return false }
        remaining = max(0, remaining - elapsed)
        remainingFraction = remaining / Self.lifetime
        return remaining == 0
    }

    package func markCopied() {
        copied = true
    }

    package func clear() {
        transcript = nil
    }
}

package struct TranscriptCardView: View {
    @ObservedObject package var model: TranscriptCardModel
    package let onCopy: () -> Void
    package let onClose: () -> Void

    package var body: some View {
        if let transcript = model.transcript {
            card(for: transcript)
        }
    }

    private func card(for transcript: UnplacedTranscript) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LoquiMark()
                Spacer(minLength: 12)
                Text(hint(for: transcript.reason))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                CountdownCloseButton(fraction: model.remainingFraction, action: onClose)
            }

            ViewThatFits(in: .vertical) {
                transcriptText(transcript.text)
                ScrollView { transcriptText(transcript.text) }
            }
            .frame(maxHeight: 150)

            HStack {
                Spacer()
                Button(action: onCopy) {
                    Group {
                        if model.copied {
                            Label("Copied", systemImage: "checkmark")
                                .foregroundStyle(LoquiBrand.mint)
                        } else {
                            Text("Copy")
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(model.isHovering ? 0.18 : 0.13)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LoquiBrand.ground.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        .onHover { model.isHovering = $0 }
    }

    private func transcriptText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.9))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(for reason: UnplacedTranscript.Reason) -> String {
        switch reason {
        case .noTextInput: "Select a text field first, then dictate"
        case .copiedToClipboard: "Couldn’t paste here, so it’s on your clipboard"
        }
    }
}

/// Loqui's Cursor Wave mark: Spectrum bars resolving into a text cursor.
private struct LoquiMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(zip([6.0, 11.0, 16.0, 8.5], LoquiBrand.spectrum)), id: \.0) { height, color in
                Capsule().fill(color).frame(width: 2.5, height: height)
            }
            ZStack {
                Rectangle().fill(.white).frame(width: 1.8, height: 17)
                VStack {
                    Rectangle().fill(.white).frame(width: 6, height: 1.8)
                    Spacer()
                    Rectangle().fill(.white).frame(width: 6, height: 1.8)
                }
            }
            .frame(width: 6, height: 17)
            .padding(.leading, 2)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// The close button doubles as the card's timer: its outline starts fully lit
/// and dims clockwise from twelve o'clock, and the card closes once the whole
/// ring is dim.
private struct CountdownCloseButton: View {
    let fraction: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 2)
                Circle()
                    .trim(from: 1 - fraction, to: 1)
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(1)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

/// A borderless panel that never activates Loqui, but can still take key
/// status so the transcript text is selectable.
private final class TranscriptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows the card above the Dock when a transcript could not be placed, and
/// removes it on Copy, on close, when the countdown ends, or when a new
/// dictation starts.
@MainActor
package final class TranscriptCardController {
    private static let copiedDismissDelay: TimeInterval = 1.2
    private static let tickInterval: TimeInterval = 1.0 / 30

    private let transcripts: AnyPublisher<UnplacedTranscript, Never>
    private let states: AnyPublisher<TranscriptionEngine.State, Never>
    private let model = TranscriptCardModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var subscriptions: Set<AnyCancellable> = []
    private var countdown: Timer?
    private var dismissWork: DispatchWorkItem?

    package convenience init(engine: TranscriptionEngine) {
        self.init(
            transcripts: engine.unplacedTranscripts.eraseToAnyPublisher(),
            states: engine.$state.eraseToAnyPublisher()
        )
    }

    package init(
        transcripts: AnyPublisher<UnplacedTranscript, Never>,
        states: AnyPublisher<TranscriptionEngine.State, Never>
    ) {
        self.transcripts = transcripts
        self.states = states
    }

    package func start() {
        transcripts
            .sink { [weak self] transcript in self?.show(transcript) }
            .store(in: &subscriptions)
        states
            .removeDuplicates()
            .sink { [weak self] state in
                switch state {
                case .requestingPermission, .starting, .recording:
                    self?.dismiss()
                case .idle, .stopping, .transcribing, .delivering, .failed:
                    break
                }
            }
            .store(in: &subscriptions)
    }

    package func stop() {
        subscriptions.removeAll()
        dismiss()
    }

    private func show(_ transcript: UnplacedTranscript) {
        dismissWork?.cancel()
        model.present(transcript)
        let panel = panel ?? makePanel()
        self.panel = panel
        hostingView?.layoutSubtreeIfNeeded()
        let size = hostingView?.fittingSize ?? NSSize(width: 500, height: 200)
        position(panel, size: size)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        startCountdown()
    }

    private func copy() {
        guard let text = model.transcript?.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        model.markCopied()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDismissDelay, execute: work)
    }

    private func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        countdown?.invalidate()
        countdown = nil
        guard let panel, panel.isVisible else {
            model.clear()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.countdown == nil else { return }
                self.panel?.orderOut(nil)
                self.model.clear()
            }
        }
    }

    private func startCountdown() {
        countdown?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.model.tick(elapsed: Self.tickInterval) {
                    self.dismiss()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let frame = FloatingPanel.frameAboveDock(size: size) else { return }
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = TranscriptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        FloatingPanel.configure(panel)
        panel.becomesKeyOnlyIfNeeded = true
        let content = TranscriptCardView(
            model: model,
            onCopy: { [weak self] in self?.copy() },
            onClose: { [weak self] in self?.dismiss() }
        )
        // Room around the card for its shadow.
        .padding(20)
        let hostingView = NSHostingView(rootView: AnyView(content))
        panel.contentView = hostingView
        self.hostingView = hostingView
        return panel
    }
}
