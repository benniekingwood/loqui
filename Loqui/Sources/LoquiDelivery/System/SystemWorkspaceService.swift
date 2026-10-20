import ApplicationServices
import AppKit
import Foundation
import LoquiCore

@MainActor
package final class SystemWorkspaceService: WorkspaceServing {
    private let workspace: NSWorkspace

    package init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    package func currentExternalTarget(excludingBundleIdentifier: String?) -> PasteTarget? {
        guard let application = workspace.frontmostApplication,
              application.bundleIdentifier != excludingBundleIdentifier else {
            return nil
        }
        return target(for: application)
    }

    package func availability(of target: PasteTarget) -> TargetProcessAvailability {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier) else {
            return .exited
        }
        return targetMatches(target, application: application) ? .available : .identityChanged
    }

    package func activate(_ target: PasteTarget) -> TargetActivationOutcome {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier) else {
            return .targetExited
        }
        guard targetMatches(target, application: application) else {
            return .identityChanged
        }
        return application.activate(options: [.activateAllWindows]) ? .requested : .rejected
    }

    package func frontmostTarget() -> PasteTarget? {
        workspace.frontmostApplication.flatMap(target(for:))
    }

    private func target(for application: NSRunningApplication) -> PasteTarget? {
        PasteTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            launchDate: application.launchDate,
            bundleURL: application.bundleURL
        )
    }

    private func targetMatches(_ target: PasteTarget, application: NSRunningApplication) -> Bool {
        Self.targetMatches(
            target,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            launchDate: application.launchDate,
            bundleURL: application.bundleURL
        )
    }

    package static func targetMatches(
        _ target: PasteTarget,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        launchDate: Date?,
        bundleURL: URL?
    ) -> Bool {
        guard let launchDate,
              processIdentifier == target.processIdentifier,
              bundleIdentifier == target.bundleIdentifier,
              launchDate == target.launchDate else {
            return false
        }
        if target.bundleURL != nil || bundleURL != nil {
            guard target.bundleURL?.standardizedFileURL == bundleURL?.standardizedFileURL else {
                return false
            }
        }
        return true
    }
}
