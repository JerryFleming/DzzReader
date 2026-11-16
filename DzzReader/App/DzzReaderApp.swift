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
    @State private var tab = AppTab.shelf
    @State private var importRequested = false
    @State private var importErrors: [String] = []
    @State private var settings = ReaderSettings()

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法整理书架", systemImage: "books.vertical", description: Text(loadError))
            } else if ready {
                TabView(selection: $tab) {
                    Tab("书架", systemImage: "books.vertical", value: AppTab.shelf) {
                        NavigationStack(path: $path) {
                            ShelfView(importRequested: $importRequested)
                                .navigationDestination(for: ShelfSection.self) { SectionView(sectionName: $0.name) }
                                .navigationDestination(for: Book.self) { book in
                                    ReaderView(book: book, context: context, settings: settings)
                                }
                        }
                    }
                    Tab("诵经", systemImage: "text.book.closed", value: AppTab.chanting) {
                        ComingSoonView(title: "诵经", systemImage: "text.book.closed")
                    }
                    Tab("分享", systemImage: "square.and.arrow.up", value: AppTab.share) {
                        ComingSoonView(title: "分享", systemImage: "square.and.arrow.up")
                    }
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
        .fileImporter(isPresented: $importRequested, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): importErrors = [error.localizedDescription]
            }
        }
        .onOpenURL { url in importFiles([url]) }
        .alert("部分文件未能导入", isPresented: Binding(get: { !importErrors.isEmpty }, set: { if !$0 { importErrors = [] } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrors.joined(separator: "\n"))
        }
    }

    private func importFiles(_ urls: [URL]) {
        var imported: [Book] = []
        var errors: [String] = []
        for url in urls {
            do {
                imported.append(try Importer.importFile(at: url, context: context))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        importErrors = errors
        if !imported.isEmpty { tab = .shelf }   // a file opened from another app lands on the shelf
        if imported.count == 1, let book = imported.first {
            path.append(book)
        }
    }
}

enum AppTab: Hashable {
    case shelf, chanting, share
}

/// Placeholder for a tab whose feature is not built yet.
struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("即将推出"))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
