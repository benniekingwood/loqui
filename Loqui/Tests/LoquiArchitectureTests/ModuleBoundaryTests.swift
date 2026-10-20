import XCTest

/// The module graph is the architecture: these tests fail the build when a
/// module reaches past its layer.
final class ModuleBoundaryTests: XCTestCase {
    func testModulesOnlyImportTheLoquiModulesTheyDependOn() throws {
        for file in try SourceTree.productionFiles() {
            let allowed = try XCTUnwrap(SourceTree.allowedLoquiImports[file.module])
            let loquiImports = file.imports.filter { $0.hasPrefix("Loqui") }
            XCTAssertTrue(
                loquiImports.isSubset(of: allowed),
                "\(file.module)/\(file.name) imports \(loquiImports.subtracting(allowed).sorted())"
            )
        }
    }

    func testCoreStaysFreeOfUIAudioAndBackendFrameworks() throws {
        let allowed: Set = ["Foundation", "Combine", "os"]
        for file in try SourceTree.productionFiles() where file.module == "LoquiCore" {
            XCTAssertTrue(file.imports.isSubset(of: allowed), "LoquiCore/\(file.name) imports \(file.imports.subtracting(allowed).sorted())")
        }
    }

    func testOnlyTheParakeetModuleSeesTheSpeechRuntime() throws {
        for file in try SourceTree.productionFiles() where file.module != "LoquiParakeet" {
            XCTAssertFalse(file.imports.contains("FluidAudio"), "\(file.module)/\(file.name) must reach FluidAudio through LoquiParakeet")
            XCTAssertFalse(file.imports.contains("CoreML"), "\(file.module)/\(file.name) must not load models directly")
        }
    }

    func testOnlyTheInterfaceAndAppDrawUI() throws {
        for file in try SourceTree.productionFiles() where !["LoquiInterface", "Loqui"].contains(file.module) {
            XCTAssertFalse(file.imports.contains("SwiftUI"), "\(file.module)/\(file.name) must not import SwiftUI")
        }
    }

    func testTheAppTargetOnlyComposesAndLaunches() throws {
        let appFiles = try SourceTree.productionFiles().filter { $0.module == "Loqui" }.map(\.name).sorted()
        XCTAssertEqual(appFiles, ["AppDelegate.swift", "AppEnvironment.swift", "LoquiApp.swift"])
    }

    func testTheSpeechRuntimeIsTheOnlyPackageDependency() throws {
        let manifest = try String(contentsOf: SourceTree.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        let dependencies = manifest.components(separatedBy: ".package(url:").dropFirst()
        XCTAssertEqual(dependencies.count, 1)
        XCTAssertTrue(dependencies.first?.contains("FluidInference/FluidAudio.git") == true)

        let resolved = try String(contentsOf: SourceTree.packageRoot.appendingPathComponent("Package.resolved"), encoding: .utf8)
        let identities = resolved.components(separatedBy: "\"identity\"").count - 1
        XCTAssertEqual(identities, 1, "FluidAudio must not pull in further packages")
    }
}
