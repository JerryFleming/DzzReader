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

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法整理书架", systemImage: "books.vertical", description: Text(loadError))
            } else if ready {
                Text("大藏经")
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
