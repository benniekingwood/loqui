@preconcurrency import AVFoundation
import AppKit
import Foundation
import os
import LoquiCore

@MainActor
package final class SystemAudioRecorderFactory: AudioRecorderCreating {
    private let inputResolver: any AudioInputResolving

    package init(inputResolver: any AudioInputResolving) {
        self.inputResolver = inputResolver
    }

    package func makeRecorder(
        at url: URL,
        eventHandler: @escaping @MainActor (RecorderEvent) -> Void
    ) throws -> any AudioRecording {
        try SystemAudioRecorder(
            url: url,
            inputResolver: inputResolver,
            eventHandler: eventHandler
        )
    }
}
