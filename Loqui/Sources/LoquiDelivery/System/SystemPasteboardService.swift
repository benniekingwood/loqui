import ApplicationServices
import AppKit
import Foundation
import LoquiCore

@MainActor
package final class SystemPasteboardService: PasteboardServing {
    private let pasteboard: NSPasteboard
    private let representationWriter: (NSPasteboardItem, Data, NSPasteboard.PasteboardType) -> Bool

    package init(
        pasteboard: NSPasteboard = .general,
        representationWriter: @escaping (NSPasteboardItem, Data, NSPasteboard.PasteboardType) -> Bool = { $0.setData($1, forType: $2) }
    ) {
        self.pasteboard = pasteboard
        self.representationWriter = representationWriter
    }

    package var changeCount: Int {
        pasteboard.changeCount
    }

    package func snapshot() -> Result<PasteboardSnapshot, PasteboardSnapshotFailure> {
        let initialChangeCount = pasteboard.changeCount
        let items = pasteboard.pasteboardItems ?? []
        var snapshots: [PasteboardItemSnapshot] = []
        for item in items {
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    return .failure(.representationReadFailed(type: type.rawValue))
                }
                representations[type.rawValue] = data
            }
            snapshots.append(PasteboardItemSnapshot(representations: representations))
        }
        guard pasteboard.changeCount == initialChangeCount else {
            return .failure(.clipboardChanged)
        }
        return .success(PasteboardSnapshot(items: snapshots))
    }

    package func replaceContents(with text: String) -> PasteboardReplacementResult {
        let originalCount = pasteboard.changeCount
        let clearedCount = pasteboard.clearContents()
        guard clearedCount != originalCount else {
            return .failed(.clearFailed, currentChangeCount: pasteboard.changeCount)
        }
        guard pasteboard.setString(text, forType: .string) else {
            return .failed(.writeFailed, currentChangeCount: pasteboard.changeCount)
        }
        guard pasteboard.string(forType: .string) == text else {
            return .failed(.verificationFailed, currentChangeCount: pasteboard.changeCount)
        }
        return .replaced(changeCount: pasteboard.changeCount)
    }

    package func restore(
        _ snapshot: PasteboardSnapshot,
        ifUnchangedSince changeCount: Int
    ) -> ClipboardRestorationOutcome {
        guard pasteboard.changeCount == changeCount else {
            return .skippedBecauseClipboardChanged
        }
        var items: [NSPasteboardItem] = []
        for snapshotItem in snapshot.items {
            let item = NSPasteboardItem()
            for (rawType, data) in snapshotItem.representations {
                let type = NSPasteboard.PasteboardType(rawType)
                guard representationWriter(item, data, type) else {
                    return .failed(.representationWriteFailed(type: rawType))
                }
            }
            items.append(item)
        }
        let beforeClear = pasteboard.changeCount
        guard beforeClear == changeCount else { return .skippedBecauseClipboardChanged }
        let clearedCount = pasteboard.clearContents()
        guard clearedCount != beforeClear else {
            return .failed(.clearFailed)
        }
        guard !items.isEmpty else {
            return .restored
        }
        guard pasteboard.writeObjects(items) else {
            return .failed(.writeFailed)
        }
        return .restored
    }
}
