import Foundation
import XCTest
@testable import LoquiCore
@testable import LoquiParakeet

final class RecordedAudioValidatorTests: XCTestCase {
    func testRecordedAudioValidatorChecksExistenceSizeFormatAndUsefulDuration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Loqui-AudioValidatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingURL = root.appendingPathComponent("missing.wav")
        let emptyURL = root.appendingPathComponent("empty.wav")
        let corruptURL = root.appendingPathComponent("corrupt.wav")
        let shortURL = root.appendingPathComponent("short.wav")
        let validURL = root.appendingPathComponent("valid.wav")
        let longURL = root.appendingPathComponent("long.wav")
        FileManager.default.createFile(atPath: emptyURL.path, contents: Data())
        try Data("not audio".utf8).write(to: corruptURL)
        try writeSilentWAV(to: shortURL, duration: 0.02)
        try writeSilentWAV(to: validURL, duration: 0.12)
        try writeSilentWAV(to: longURL, duration: 0.3)

        let validator = RecordedAudioValidator(
            minimumUsefulDuration: 0.05,
            maximumUsefulDuration: 0.2
        )

        XCTAssertEqual(validator.validateAudio(at: missingURL), .invalid(.missing))
        XCTAssertEqual(validator.validateAudio(at: emptyURL), .invalid(.empty))
        XCTAssertEqual(validator.validateAudio(at: corruptURL), .invalid(.unreadableFormat))
        guard case .invalid(.tooShort) = validator.validateAudio(at: shortURL) else {
            return XCTFail("Expected short audio rejection")
        }
        guard case let .valid(duration) = validator.validateAudio(at: validURL) else {
            return XCTFail("Expected valid audio")
        }
        XCTAssertEqual(duration, 0.12, accuracy: 0.01)
        guard case .invalid(.tooLong) = validator.validateAudio(at: longURL) else {
            return XCTFail("Expected long audio rejection")
        }
    }

    private func writeSilentWAV(to url: URL, duration: TimeInterval) throws {
        let sampleRate: UInt32 = 16_000
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let frameCount = UInt32(duration * Double(sampleRate))
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let audioByteCount = frameCount * UInt32(blockAlign)

        var data = Data("RIFF".utf8)
        appendLittleEndian(36 + audioByteCount, to: &data)
        data.append(Data("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(Data("data".utf8))
        appendLittleEndian(audioByteCount, to: &data)
        data.append(Data(repeating: 0, count: Int(audioByteCount)))
        try data.write(to: url)
    }

    private func appendLittleEndian(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
