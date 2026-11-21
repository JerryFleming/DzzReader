import Foundation
import SwiftData
import DzzCore

enum ChantImportError: Error, LocalizedError {
    case unreadable(String)
    case invalid(String, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "无法读取「\(name)」。"
        case .invalid(let name, let reason): "「\(name)」：\(reason)"
        }
    }
}

/// The 诵经 shelf's texts: JSON files bundled under `ChantingTexts/`, plus ones imported at runtime into
/// `Documents/ImportedChanting/`.
@MainActor
enum ChantLibrary {
    static let bundledFolder = "ChantingTexts"

    static var importedDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "ImportedChanting")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Ids of bundled texts the reader deleted; the files stay in the app bundle, so they are skipped on sync.
    static let deletedBundledKey = "chant.deletedBundled"

    /// Registers every bundled JSON file (except deleted ones) and drops entries whose file is gone.
    static func syncBundled(resourceRoot: URL = Bundle.main.resourceURL!, context: ModelContext,
                            defaults: UserDefaults = .standard) throws {
        let deleted = Set(defaults.stringArray(forKey: deletedBundledKey) ?? [])
        let folder = resourceRoot.appending(path: bundledFolder)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let bundled = BookSource.bundled.rawValue
        let existing = try context.fetch(FetchDescriptor<ChantBook>(predicate: #Predicate { $0.sourceRaw == bundled }))
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (order, file) in files.enumerated() {
            let name = file.lastPathComponent
            let id = "bundled:\(name)"
            if deleted.contains(id) { continue }
            let title = (name as NSString).deletingPathExtension
            if let book = byID.removeValue(forKey: id) {
                book.title = title
                book.catalogOrder = order
                book.relativePath = "\(bundledFolder)/\(name)"
            } else {
                context.insert(ChantBook(id: id, title: title, source: .bundled,
                                         relativePath: "\(bundledFolder)/\(name)", catalogOrder: order))
            }
        }
        for gone in byID.values { context.delete(gone) }
        if context.hasChanges { try context.save() }
    }

    /// Validates the file as a chanting item list, copies it in and adds it to the shelf. Title is the file name.
    @discardableResult
    static func importFile(at url: URL, context: ModelContext) throws -> ChantBook {
        let name = url.lastPathComponent
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChantImportError.unreadable(name)
        }
        do {
            _ = try ChantDocument.parse(data)
        } catch {
            throw ChantImportError.invalid(name, error.localizedDescription)
        }

        let id = UUID().uuidString
        try data.write(to: importedDirectory.appending(path: "\(id).json"), options: .atomic)
        let book = ChantBook(id: id, title: (name as NSString).deletingPathExtension, source: .imported,
                             relativePath: "ImportedChanting/\(id).json")
        context.insert(book)
        try context.save()

        if url.path.contains("/Inbox/") {   // handed over by another app; our copy is the one that matters
            try? FileManager.default.removeItem(at: url)
        }
        return book
    }

    /// Imported texts lose their file; bundled ones are remembered as deleted so launch doesn't re-add them.
    static func delete(_ books: [ChantBook], context: ModelContext, defaults: UserDefaults = .standard) throws {
        var deleted = defaults.stringArray(forKey: deletedBundledKey) ?? []
        for book in books {
            if book.source == .imported {
                try? FileManager.default.removeItem(at: book.fileURL)
            } else if !deleted.contains(book.id) {
                deleted.append(book.id)
            }
            context.delete(book)
        }
        defaults.set(deleted, forKey: deletedBundledKey)
        try context.save()
    }

    static func delete(_ book: ChantBook, context: ModelContext, defaults: UserDefaults = .standard) throws {
        try delete([book], context: context, defaults: defaults)
    }

    /// Parses off the main thread.
    static func load(_ book: ChantBook) async throws -> ChantDocument {
        let url = book.fileURL
        return try await Task.detached(priority: .userInitiated) {
            try ChantDocument.parse(try Data(contentsOf: url))
        }.value
    }
}
