import Foundation

/// Reads the package's own sources so tests can enforce structure that the
/// compiler alone does not: module layering, logging privacy, and the absence
/// of anything inherited from the project Loqui started from.
enum SourceTree {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let repositoryRoot = packageRoot.deletingLastPathComponent()

    /// Production modules and the Loqui modules each may import. Mirrors the
    /// target graph in Package.swift; a new edge must be added in both places.
    static let allowedLoquiImports: [String: Set<String>] = [
        "LoquiCore": [],
        "LoquiAudio": ["LoquiCore"],
        "LoquiParakeet": ["LoquiCore"],
        "LoquiDelivery": ["LoquiCore"],
        "LoquiShortcuts": ["LoquiCore"],
        "LoquiInterface": ["LoquiCore", "LoquiAudio", "LoquiShortcuts"],
        "Loqui": ["LoquiCore", "LoquiAudio", "LoquiParakeet", "LoquiDelivery", "LoquiShortcuts", "LoquiInterface"],
    ]

    struct SourceFile {
        let module: String
        let url: URL
        let text: String

        var name: String { url.lastPathComponent }

        var imports: Set<String> {
            Set(text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard let index = words.firstIndex(of: "import"), index == words.startIndex
                    || words[words.startIndex] == "@preconcurrency" else { return nil }
                return words.last.map(String.init)
            })
        }
    }

    static func productionFiles() throws -> [SourceFile] {
        try allowedLoquiImports.keys.sorted().flatMap { module in
            try swiftFiles(in: packageRoot.appendingPathComponent("Sources/\(module)", isDirectory: true))
                .map { try SourceFile(module: module, url: $0, text: String(contentsOf: $0, encoding: .utf8)) }
        }
    }

    static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    }

    /// Every file git tracks, read as text where possible.
    static func trackedTextFiles() throws -> [(path: String, text: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryRoot.path, "ls-files", "-z"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let paths = (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\0").map(String.init)
        return paths.compactMap { path in
            let url = repositoryRoot.appendingPathComponent(path)
            guard let contents = try? Data(contentsOf: url), let text = String(data: contents, encoding: .utf8) else {
                return nil
            }
            return (path, text)
        }
    }
}
