import Foundation
import SwiftData

extension ModelContainer {
    static let schema = Schema([Book.self, ReadingProgress.self, Bookmark.self, ChantBook.self])

    static func app() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
    }

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
}
