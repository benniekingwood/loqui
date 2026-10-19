import Testing
@testable import Loqui

@MainActor
@Test func packageLoadsCoreEngineTypes() {
    #expect(TranscriptionEngine.maximumRecordingDuration == 300)
}
