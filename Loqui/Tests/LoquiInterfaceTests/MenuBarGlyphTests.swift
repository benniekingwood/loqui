import AppKit
import XCTest
@testable import LoquiCore
@testable import LoquiInterface

final class MenuBarGlyphTests: XCTestCase {
    func testGlyphsAreTemplateImagesAtMenuBarSize() {
        for image in [MenuBarGlyph.idle, MenuBarGlyph.recording] {
            XCTAssertTrue(image.isTemplate, "macOS only tints template images for light and dark menu bars")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        }
    }

    func testRecordingGlyphDiffersFromIdle() throws {
        let idle = try XCTUnwrap(pixels(of: MenuBarGlyph.idle))
        let recording = try XCTUnwrap(pixels(of: MenuBarGlyph.recording))
        XCTAssertNotEqual(idle, recording)
        XCTAssertTrue(idle.contains { $0 != 0 }, "idle glyph must draw something")
    }

    func testImageLookupMatchesState() {
        XCTAssertTrue(MenuBarGlyph.image(recording: true) === MenuBarGlyph.recording)
        XCTAssertTrue(MenuBarGlyph.image(recording: false) === MenuBarGlyph.idle)
    }

    private func pixels(of image: NSImage) -> [UInt8]? {
        var rect = NSRect(x: 0, y: 0, width: 36, height: 36)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.bitmapData else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }
}
