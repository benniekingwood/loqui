import Foundation

@MainActor
package protocol RecordingReadyCuePlaying: AnyObject {
    func play() async
    func stop()
}

@MainActor
package protocol RecordingStoppedCuePlaying: AnyObject {
    func play()
    func stop()
}
