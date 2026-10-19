import SwiftUI

@main
struct LoquiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.transcriptionEngine)
                .environmentObject(appDelegate.hotKeyController)
                .environmentObject(appDelegate.audioInputSelection)
        } label: {
            MenuBarIcon()
                .environmentObject(appDelegate.transcriptionEngine)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarIcon: View {
    @EnvironmentObject var engine: TranscriptionEngine

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(recording: engine.state == .recording))
            .accessibilityLabel(engine.state == .recording ? "Recording" : "Loqui")
    }
}
