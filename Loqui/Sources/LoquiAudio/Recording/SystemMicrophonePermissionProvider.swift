@preconcurrency import AVFoundation
import AppKit
import Foundation
import os
import LoquiCore

@MainActor
package final class SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    package init() {}

    package func authorizationStatus() -> MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    package func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
