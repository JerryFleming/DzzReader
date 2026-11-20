import Foundation
import SwiftData

/// A chanting text on the 诵经 shelf: a JSON item list of characters with pinyin (see `ChantDocument`).
/// Kept apart from `Book` so the 书架 tab's catalogue queries never see these, and vice versa.
@Model
final class ChantBook {
    @Attribute(.unique) var id: String      // "bundled:<file name>" or a UUID string for imports
    var title: String
    var sourceRaw: String                   // BookSource.rawValue; predicates cannot capture enums
    var relativePath: String                // "ChantingTexts/佛教念诵集.json" | "ImportedChanting/<uuid>.json"
    var catalogOrder: Int
    var dateAdded: Date
    var lastOpened: Date?

    init(id: String, title: String, source: BookSource, relativePath: String, catalogOrder: Int = 0, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.sourceRaw = source.rawValue
        self.relativePath = relativePath
        self.catalogOrder = catalogOrder
        self.dateAdded = dateAdded
    }

    var source: BookSource {
        get { BookSource(rawValue: sourceRaw) ?? .bundled }
        set { sourceRaw = newValue.rawValue }
    }

    var fileURL: URL {
        switch source {
        case .bundled: Bundle.main.resourceURL!.appending(path: relativePath)
        case .imported: URL.documentsDirectory.appending(path: relativePath)
        }
    }
}
