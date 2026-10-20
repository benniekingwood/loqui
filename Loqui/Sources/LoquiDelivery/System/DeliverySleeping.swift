import Foundation
import LoquiCore

@MainActor
package protocol DeliverySleeping: AnyObject {
    func sleep(for duration: TimeInterval) async -> Bool
}

@MainActor
package final class SystemDeliverySleeper: DeliverySleeping {
    package func sleep(for duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(max(0, duration)))
            return true
        } catch {
            return false
        }
    }
}
