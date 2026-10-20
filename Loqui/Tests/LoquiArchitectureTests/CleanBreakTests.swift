import XCTest

/// Loqui stands on its own. Nothing in the repository may point back to the
/// project it was originally derived from, or to that project's owner or
/// signing team, except the README's Acknowledgments section, which credits
/// it. The names are stored reversed so this file does not contain the very
/// strings it forbids.
final class CleanBreakTests: XCTestCase {
    private static let forbidden = ["txetklat", "ualbeoj", "2U4H24G87K"].map { String($0.reversed()) }

    func testNoTrackedFileReferencesTheOriginalProject() throws {
        let files = try SourceTree.trackedTextFiles()
        XCTAssertGreaterThan(files.count, 50, "Expected to scan the whole repository")
        for (path, text) in files {
            let lowered = Self.withoutAcknowledgments(text, path: path).lowercased()
            for name in Self.forbidden {
                XCTAssertFalse(lowered.contains(name.lowercased()), "\(path) references \(name)")
            }
        }
    }

    func testTheReadmeCreditsTheOriginalProjectOnlyInAcknowledgments() throws {
        let readme = try XCTUnwrap(SourceTree.trackedTextFiles().first { $0.path == "README.md" }?.text)
        let credited = Self.forbidden.dropLast().allSatisfy { readme.lowercased().contains($0) }
        XCTAssertTrue(credited, "README.md should credit the original project")
        XCTAssertNotEqual(Self.withoutAcknowledgments(readme, path: "README.md"), readme)
    }

    func testNoTrackedPathCarriesTheOriginalName() throws {
        for (path, _) in try SourceTree.trackedTextFiles() {
            for name in Self.forbidden {
                XCTAssertFalse(path.lowercased().contains(name.lowercased()), "\(path) carries \(name)")
            }
        }
    }

    /// Drops the README's `## Acknowledgments` section, up to the next heading
    /// of the same level, so the credit there is the only allowed mention.
    private static func withoutAcknowledgments(_ text: String, path: String) -> String {
        guard path == "README.md" else { return text }
        var kept: [Substring] = []
        var skipping = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                skipping = line == "## Acknowledgments"
            }
            if !skipping {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }
}
