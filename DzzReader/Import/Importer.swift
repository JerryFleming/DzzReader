import Foundation
import SwiftData

/// Placeholder until Task 10; the shelf's swipe-to-delete needs the symbol.
@MainActor
enum Importer {
    static func delete(_ book: Book, context: ModelContext) throws {
        context.delete(book)
        try context.save()
    }
}
