import AppKit
import SwiftUI
import LoquiAudio
import LoquiCore
import LoquiShortcuts

/// Loqui's Settings window: the dictation shortcut, the microphone, sound
/// cues, and what the speech model supports.
package struct SettingsView: View {
    @EnvironmentObject package var engine: TranscriptionEngine
    @EnvironmentObject package var hotKeyController: HotKeyController
    @EnvironmentObject package var audioInputSelection: AudioInputSelection
    @ObservedObject package var recorder: ShortcutRecorder
    @AppStorage(RecordingCuePreference.defaultsKey) private var playsSoundCues = true
    @AppStorage(RecordingOverlayPreference.defaultsKey) private var showsRecordingOverlay = true

    package var body: some View {
        Form {
            Section {
                header
            }

            Section("Shortcuts") {
                LabeledContent {
                    ShortcutField(key: hotKeyController.shortcut.key, recorder: recorder)
                } label: {
                    Text("Push to talk")
                    Text("Hold to dictate. Release to insert the text.")
                }

                if let message = recorder.message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: doubleTapLocksBinding) {
                    Text("Hands-free mode")
                    Text("Double-tap \(hotKeyController.shortcut.key.displayName) to start. Tap it again to stop.")
                }

                if hotKeyController.shortcut.key == .function {
                    Label(
                        "So macOS doesn’t also react to the Globe key, set Keyboard › “Press 🌐 key to” to “Do Nothing” in System Settings.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                if let recoveryMessage = hotKeyController.availability.recoveryMessage {
                    HStack {
                        Label(recoveryMessage, systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Retry") { hotKeyController.retry() }
                    }
                }

                if hotKeyController.shortcut != .default {
                    Button("Reset to Default") { hotKeyController.update(.default) }
                        .disabled(recorder.isRecording)
                }
            }

            Section("Microphone") {
                Picker(selection: inputSelectionBinding) {
                    Text(systemDefaultTitle).tag(AudioInputPreference.systemDefault)
                    ForEach(audioInputSelection.devices) { device in
                        Text(device.name).tag(AudioInputPreference.device(uid: device.uid))
                    }
                    if audioInputSelection.isPreferredDeviceMissing {
                        Text("Disconnected Device").tag(audioInputSelection.preference)
                    }
                } label: {
                    Text("Input device")
                    Text("System Default follows Sound settings.")
                }
                .disabled(!engine.isInteractive)
            }

            Section("Feedback") {
                Toggle(isOn: $playsSoundCues) {
                    Text("Sound cues")
                    Text("Play a chime when recording starts and stops.")
                }
                Toggle(isOn: $showsRecordingOverlay) {
                    Text("Recording indicator")
                    Text("Show a floating bar above the Dock while Loqui listens and transcribes.")
                }
            }

            Section("Speech") {
                LabeledContent("Language", value: "English")
                LabeledContent("Model", value: "Parakeet TDT 0.6B v2, on this Mac")
            }
        }
        .formStyle(.grouped)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("loqui")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                Text("Version \(appVersion) · Private, on-device dictation")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var doubleTapLocksBinding: Binding<Bool> {
        Binding(
            get: { hotKeyController.shortcut.doubleTapLocks },
            set: { doubleTapLocks in
                var shortcut = hotKeyController.shortcut
                shortcut.doubleTapLocks = doubleTapLocks
                hotKeyController.update(shortcut)
            }
        )
    }

    private var systemDefaultTitle: String {
        guard case .systemDefault = audioInputSelection.preference else { return "System Default" }
        return audioInputSelection.selectionSummary
    }

    private var inputSelectionBinding: Binding<AudioInputPreference> {
        Binding(get: { audioInputSelection.preference }, set: { audioInputSelection.select($0) })
    }
}

/// Shows the dictation key as a keycap, or a prompt while a new key is recorded.
private struct ShortcutField: View {
    let key: DictationKey
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                Text("Press a modifier key…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    )
                Button("Cancel") { recorder.cancel() }
            } else {
                KeyCap(key: key)
                Button("Change") { recorder.start() }
            }
        }
    }
}

private struct KeyCap: View {
    let key: DictationKey

    var body: some View {
        HStack(spacing: 5) {
            Text(key.symbol)
            Text(key.displayName)
        }
        .fontWeight(.medium)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.displayName)
    }
}
