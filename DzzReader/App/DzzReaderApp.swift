import SwiftData
import SwiftUI
import UniformTypeIdentifiers
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
    @State private var chantPath = NavigationPath()
    @State private var tab = AppTab.shelf
    @State private var importRequested = false
    @State private var importErrors: [String] = []
    @State private var settings = ReaderSettings()
    @AppStorage("share.quote") private var shareMarkup = QuoteScript.sample
    @State private var quoteInbox = QuoteInbox()

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
                        NavigationStack(path: $chantPath) {
                            ChantShelfView(path: $chantPath)
                                .navigationDestination(for: ChantBook.self) { book in
                                    ChantReaderView(book: book, settings: settings)
                                }
                        }
                    }
                    Tab("分享", systemImage: "square.and.arrow.up", value: AppTab.share) {
                        ShareView()
                    }
                }
                // A selection shared from the reader fills the card's text box and opens the tab;
                // the book stays open on the shelf tab underneath.
                .environment(quoteInbox)
                .onChange(of: quoteInbox.pending) { _, markup in
                    guard let markup else { return }
                    shareMarkup = markup
                    tab = .share
                    quoteInbox.pending = nil   // so sending the same text again still arrives
                }
            } else {
                ProgressView("正在整理书架…")
            }
        }
        .task {
            do {
                try ChantLibrary.syncBundled(context: context)
                ready = true
            } catch {
                loadError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importRequested, allowedContentTypes: [.plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): importErrors = [error.localizedDescription]
            }
        }
        .onOpenURL { url in
            // Each shelf takes its own kind: JSON chanting texts go to 诵经, plain-text books to 书架.
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .json) == true {
                importChantFile(url)
            } else if type?.conforms(to: .plainText) == true {
                importFiles([url])
            } else {
                importErrors = ["「\(url.lastPathComponent)」不是 txt 或 JSON 文件。"]
            }
        }
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

extension RootView {
    /// A JSON file opened from another app is a chanting text: add it to the 诵经 shelf and open it.
    private func importChantFile(_ url: URL) {
        do {
            let book = try ChantLibrary.importFile(at: url, context: context)
            tab = .chanting
            chantPath.append(book)
        } catch {
            importErrors = [error.localizedDescription]
        }
    }
}

/// Carries `书名•卷名::文字` markup from the reader to the 分享 tab. A single long-lived object in
/// the environment (rather than a closure, which SwiftUI cannot compare) so readers of it are not
/// invalidated on every update; RootView watches `pending` and delivers it.
@Observable @MainActor
final class QuoteInbox {
    var pending: String?

    func send(_ markup: String) { pending = markup }
}

enum AppTab: Hashable {
    case shelf, chanting, share
}
