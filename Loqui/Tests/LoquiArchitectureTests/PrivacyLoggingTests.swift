import XCTest

/// Dictated text and clipboard contents are private. These tests scan every
/// production module for log or status interpolations that could render them.
final class PrivacyLoggingTests: XCTestCase {
    func testLoggingNeverInterpolatesRawTranscriptOrClipboardVariables() throws {
        let rawUserContentInterpolation = #"\\\((?:text|transcript|transcription|cleaned|clipboardContents)(?!\.count)"#
        for file in try SourceTree.productionFiles() {
            XCTAssertNil(
                file.text.range(of: rawUserContentInterpolation, options: .regularExpression),
                "\(file.module)/\(file.name) must not interpolate raw transcript or clipboard variables"
            )
            XCTAssertFalse(file.text.contains("Transcription: '"))
            XCTAssertFalse(file.text.contains("Inserted transcription:"))
        }
    }

    func testLoggedModelPathsUsePrivateHashMask() throws {
        let files = try SourceTree.productionFiles().filter { $0.text.contains("Logger(") || $0.text.contains("os_log") }
        var checked = 0
        for file in files {
            let expression = try NSRegularExpression(pattern: #"\\\([^)]*\.(?:location|url)\.path[^)]*\)"#)
            let range = NSRange(file.text.startIndex..., in: file.text)
            for match in expression.matches(in: file.text, range: range) {
                let interpolation = String(file.text[Range(match.range, in: file.text)!])
                guard file.text.contains("Logger") else { continue }
                checked += 1
                XCTAssertTrue(
                    interpolation.contains(".private(mask: .hash)"),
                    "\(file.module)/\(file.name) logs a path without a private hash mask: \(interpolation)"
                )
            }
        }
        XCTAssertGreaterThan(checked, 0, "Expected the model location to be logged")
    }

    func testEveryLoggedInterpolationStatesItsPrivacy() throws {
        // Every interpolation in a Logger call must state its privacy level, so
        // nothing reaches the unified log without a deliberate decision.
        var checked = 0
        for file in try SourceTree.productionFiles() {
            for call in Self.loggerCalls(in: file.text) {
                for interpolation in Self.interpolations(in: call) {
                    checked += 1
                    XCTAssertTrue(interpolation.contains("privacy:"), "\(file.module)/\(file.name): \\(\(interpolation))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 10, "Expected to inspect the app's log statements")
    }

    /// The argument text of each `logger.level(...)` call, with balanced parentheses.
    private static func loggerCalls(in text: String) -> [Substring] {
        let levels = ["debug", "info", "notice", "error", "fault"]
        var calls: [Substring] = []
        var index = text.startIndex
        while let range = text.range(of: "Logger.", options: [], range: index ..< text.endIndex)
            ?? text.range(of: "ogger.", options: [], range: index ..< text.endIndex) {
            index = range.upperBound
            guard let level = levels.first(where: { text[index...].hasPrefix($0 + "(") }) else { continue }
            let open = text.index(index, offsetBy: level.count)
            if let close = matchingParenthesis(in: text, from: open) {
                calls.append(text[open ... close])
                index = close
            }
        }
        return calls
    }

    /// The contents of each `\\(...)` string interpolation in a call.
    private static func interpolations(in call: Substring) -> [Substring] {
        var found: [Substring] = []
        var index = call.startIndex
        while let range = call.range(of: "\\(", options: [], range: index ..< call.endIndex) {
            let open = call.index(before: range.upperBound)
            guard let close = matchingParenthesis(in: call, from: open) else { break }
            found.append(call[call.index(after: open) ..< close])
            index = close
        }
        return found
    }

    private static func matchingParenthesis<S: StringProtocol>(in text: S, from open: S.Index) -> S.Index? {
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }
}
