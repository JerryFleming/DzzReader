import SwiftData
import SwiftUI
import DzzCore

@main
struct DzzReaderApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.app()
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// Loads the catalog once, then shows the shelf.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var ready = false
    @State private var loadError: String?
    @State private var path = NavigationPath()
    @State private var importRequested = false

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法整理书架", systemImage: "books.vertical", description: Text(loadError))
            } else if ready {
                NavigationStack(path: $path) {
                    ShelfView(importRequested: $importRequested)
                        .navigationDestination(for: ShelfSection.self) { SectionView(sectionName: $0.name) }
                        .navigationDestination(for: Book.self) { book in Text(book.title) }
                }
            } else {
                ProgressView("正在整理书架…")
            }
        }
        .task {
            do {
                let books = Bundle.main.resourceURL!.appending(path: "Books")
                _ = try CatalogLoader.loadIfNeeded(booksDirectory: books, context: context)
                ready = true
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
