import XCTest

/// Loqui stands on its own. Nothing in the repository may point back to the
/// project it was originally derived from, or to that project's owner or
/// signing team. The names are stored reversed so this file does not contain
/// the very strings it forbids.
final class CleanBreakTests: XCTestCase {
    private static let forbidden = ["txetklat", "uaolbeoj", "2U4H24G87K"].map { String($0.reversed()) }

    func testNoTrackedFileReferencesTheOriginalProject() throws {
        let files = try SourceTree.trackedTextFiles()
        XCTAssertGreaterThan(files.count, 50, "Expected to scan the whole repository")
        for (path, text) in files {
            let lowered = text.lowercased()
            for name in Self.forbidden {
                XCTAssertFalse(lowered.contains(name.lowercased()), "\(path) references \(name)")
            }
        }
    }

    func testNoTrackedPathCarriesTheOriginalName() throws {
        for (path, _) in try SourceTree.trackedTextFiles() {
            for name in Self.forbidden {
                XCTAssertFalse(path.lowercased().contains(name.lowercased()), "\(path) carries \(name)")
            }
        }
    }
}
