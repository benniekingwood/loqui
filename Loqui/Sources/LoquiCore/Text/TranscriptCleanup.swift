import Foundation

/// Deterministic rewrites applied to a transcript before it is delivered. No
/// model is involved, so the same words always produce the same text.
///
/// Drafts only lose filler words. Spoken formatting applies to the final
/// transcript alone, so a draft never types a line break while the speaker is
/// still mid-sentence.
package struct TranscriptCleanup: Equatable, Sendable {
    package var removesFillerWords: Bool
    package var appliesSpokenFormatting: Bool

    package static let none = TranscriptCleanup(removesFillerWords: false, appliesSpokenFormatting: false)

    package init(removesFillerWords: Bool, appliesSpokenFormatting: Bool) {
        self.removesFillerWords = removesFillerWords
        self.appliesSpokenFormatting = appliesSpokenFormatting
    }

    /// The cleanup the Settings toggles currently ask for.
    package init(defaults: UserDefaults) {
        removesFillerWords = FillerWordPreference.isEnabled(in: defaults)
        appliesSpokenFormatting = SpokenFormattingPreference.isEnabled(in: defaults)
    }

    package func finalTranscript(_ text: String) -> String {
        var text = text
        if appliesSpokenFormatting { text = SpokenFormatting.apply(to: text) }
        if removesFillerWords { text = FillerWords.remove(from: text) }
        // Keep line breaks the speaker asked for at either end.
        return text.trimmingCharacters(in: .whitespaces)
    }

    package func draftTranscript(_ text: String) -> String {
        guard removesFillerWords else { return text }
        return FillerWords.remove(from: text).trimmingCharacters(in: .whitespaces)
    }

    /// A transcript that was nothing but fillers becomes `.noSpeech`.
    package func apply(to outcome: TranscriptionOutcome) -> TranscriptionOutcome {
        guard case let .success(text) = outcome else { return outcome }
        let cleaned = finalTranscript(text)
        return cleaned.isEmpty ? .noSpeech : .success(cleaned)
    }
}

/// Removes the hesitations a speech model writes down verbatim ("um", "uh",
/// "erm", ...). A filler matches only as a whole word, lowercase or with just
/// its first letter capitalized, so "umbrella", "uh-huh", and "ER" stay. The
/// comma or ellipsis after a filler goes with it, the surrounding spaces close
/// up, and a filler that started a sentence hands its capital to the next word.
///
/// Behavior follows Hex's filler-word pass (github.com/anomalyco/hex, MIT).
package enum FillerWords {
    static let words = ["um", "umm", "uh", "uhh", "erm", "er", "ah"].map(Array.init)

    package static func remove(from transcript: String) -> String {
        let characters = Array(transcript)
        var output = ""
        var index = 0
        // A filler was just removed, so the next character decides the spacing.
        var removed = false
        var capitalizeNext = false

        while index < characters.count {
            if let end = fillerEnd(in: characters, at: index) {
                output.trimTrailing()
                if !removed {
                    capitalizeNext = characters[index].isUppercase && output.endsSentence
                }
                index = continuation(after: end, in: characters)
                removed = true
                continue
            }

            let character = characters[index]
            index += 1
            if removed {
                if character.isInlineSpace { continue }
                if character == "\n" {
                    removed = false
                    capitalizeNext = false
                    output.append(character)
                    continue
                }
                if ".!?,".contains(character), output.endsSentence { continue }
                removed = false
                let isStraightClosingQuote = character == "\""
                    && (index == characters.count || !characters[index].isWordCharacter)
                if ".,;:!?)]}”’…".contains(character) || isStraightClosingQuote {
                    output.trimTrailing(also: [","])
                    capitalizeNext = false
                } else {
                    if output.needsSpaceBeforeWord { output.append(" ") }
                    if capitalizeNext {
                        capitalizeNext = false
                        output.append(character.uppercased())
                        continue
                    }
                }
            }
            output.append(character)
        }
        if removed { output.trimTrailing(also: [","]) }
        return output
    }

    private static func fillerEnd(in characters: [Character], at start: Int) -> Int? {
        if start > 0, characters[start - 1].joinsWord { return nil }
        for word in words {
            let end = start + word.count
            guard end <= characters.count else { continue }
            let matches = zip(characters[start ..< end], word).enumerated().allSatisfy { offset, pair in
                pair.0 == pair.1 || (offset == 0 && String(pair.0) == pair.1.uppercased())
            }
            if matches, end == characters.count || !characters[end].joinsWord {
                return end
            }
        }
        return nil
    }

    /// Where the text resumes after a filler ending at `end`, past its own
    /// comma or ellipsis.
    private static func continuation(after end: Int, in characters: [Character]) -> Int {
        var index = skipInlineSpaces(in: characters, from: end)
        if index < characters.count {
            if characters[index] == "," || characters[index] == "…" {
                index += 1
            } else if characters[index...].starts(with: "...") {
                index += 3
            }
        }
        return skipInlineSpaces(in: characters, from: index)
    }
}

/// Turns spoken formatting commands into the formatting itself: "new line" and
/// "line break" become a line break, "new paragraph" a blank line, and "open
/// quote" / "close quote" quotation marks. Commands match as whole words in any
/// case ("newline" and "new liner" stay), and the commas and periods a model
/// puts around a command go with it.
///
/// Behavior follows Hex's spoken-formatting pass (github.com/anomalyco/hex, MIT).
package enum SpokenFormatting {
    private enum Command {
        case lineBreaks(String)
        case openQuote
        case closeQuote
    }

    private static let commands: [(words: [String], command: Command)] = [
        (["new", "paragraph"], .lineBreaks("\n\n")),
        (["new", "line"], .lineBreaks("\n")),
        (["line", "break"], .lineBreaks("\n")),
        (["open", "quote"], .openQuote),
        (["close", "quote"], .closeQuote),
    ]

    package static func apply(to transcript: String) -> String {
        let characters = Array(transcript)
        var output = ""
        var index = 0
        while index < characters.count {
            let startsWord = index == 0 || !characters[index - 1].isWordCharacter
            if startsWord, let (command, end) = command(in: characters, at: index) {
                index = emit(command, into: &output, characters: characters, end: end)
                continue
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }

    private static func command(in characters: [Character], at start: Int) -> (Command, Int)? {
        candidates: for (words, command) in commands {
            var position = start
            for (offset, word) in words.enumerated() {
                if offset > 0 {
                    let wordStart = characters[position...].firstIndex { !$0.isWhitespace } ?? characters.count
                    guard wordStart > position else { continue candidates }
                    position = wordStart
                }
                for expected in word {
                    guard position < characters.count,
                          characters[position].lowercased() == String(expected) else {
                        continue candidates
                    }
                    position += 1
                }
            }
            if position == characters.count || !characters[position].isWordCharacter {
                return (command, position)
            }
        }
        return nil
    }

    /// Writes `command` and returns where the text continues.
    private static func emit(_ command: Command, into output: inout String, characters: [Character], end: Int) -> Int {
        switch command {
        case let .lineBreaks(breaks):
            output.trimTrailing(also: [",", ";"])
            output.append(breaks)
            return skipInlineSpaces(in: characters, from: end, also: [",", ".", ";", ":"])
        case .openQuote:
            output.trimTrailing()
            if let last = output.last, !"\n([\"".contains(last) {
                output.append(" ")
            }
            output.append("\"")
            return skipInlineSpaces(in: characters, from: end, also: [",", "."])
        case .closeQuote:
            output.trimTrailing(also: [","])
            output.append("\"")
            let next = skipInlineSpaces(in: characters, from: end)
            if next < characters.count, characters[next].isWordCharacter {
                output.append(" ")
            }
            return next
        }
    }
}

private func skipInlineSpaces(in characters: [Character], from start: Int, also: Set<Character> = []) -> Int {
    var index = start
    while index < characters.count, characters[index].isInlineSpace || also.contains(characters[index]) {
        index += 1
    }
    return index
}

private extension Character {
    var isInlineSpace: Bool { isWhitespace && self != "\n" }
    var isWordCharacter: Bool { isLetter || isNumber }
    var joinsWord: Bool { isWordCharacter || self == "-" || self == "'" || self == "’" }
}

private extension String {
    var endsSentence: Bool {
        guard let last else { return true }
        return ".!?\n".contains(last)
    }

    var needsSpaceBeforeWord: Bool {
        guard let last else { return false }
        if "\n([{“‘".contains(last) { return false }
        if last == "\"" {
            return dropLast().last.map { !$0.isWhitespace } ?? false
        }
        return true
    }

    mutating func trimTrailing(also extra: Set<Character> = []) {
        while let last, last.isInlineSpace || extra.contains(last) {
            removeLast()
        }
    }
}
