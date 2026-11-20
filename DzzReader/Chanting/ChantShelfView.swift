import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The 诵经 tab's shelf: recently read, bundled 念诵 texts, and imported ones.
struct ChantShelfView: View {
    @Query(sort: \ChantBook.catalogOrder) private var books: [ChantBook]
    @Environment(\.modelContext) private var context
    @Binding var path: NavigationPath
    @State private var importRequested = false
    @State private var importErrors: [String] = []

    private var recents: [ChantBook] {
        books.filter { $0.lastOpened != nil }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            .prefix(5).map { $0 }
    }

    private var bundled: [ChantBook] { books.filter { $0.source == .bundled } }

    private var imported: [ChantBook] {
        books.filter { $0.source == .imported }.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        List {
            if !recents.isEmpty {
                Section("最近阅读") {
                    ForEach(recents) { book in
                        NavigationLink(value: book) { ChantBookRow(book: book) }
                    }
                }
            }
            if !bundled.isEmpty {
                Section("念诵集") {
                    ForEach(bundled) { book in
                        NavigationLink(value: book) { ChantBookRow(book: book) }
                    }
                }
            }
            if !imported.isEmpty {
                Section("导入的文本") {
                    ForEach(imported) { book in
                        NavigationLink(value: book) { ChantBookRow(book: book) }
                    }
                    .onDelete { offsets in
                        for index in offsets { try? ChantLibrary.delete(imported[index], context: context) }
                    }
                }
            }
        }
        .overlay {
            if books.isEmpty {
                ContentUnavailableView("没有诵经文本", systemImage: "text.book.closed",
                                       description: Text("轻点右上角导入 JSON 文本"))
            }
        }
        .accessibilityIdentifier("chantShelf")
        .navigationTitle("诵经")                       // back-button title on pushed pages
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .fileImporter(isPresented: $importRequested, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): importErrors = [error.localizedDescription]
            }
        }
        .alert("部分文件未能导入", isPresented: Binding(get: { !importErrors.isEmpty }, set: { if !$0 { importErrors = [] } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrors.joined(separator: "\n"))
        }
    }

    /// Same shape as the 书架 top bar: a heading where the search field sits there, import on the right.
    private var topBar: some View {
        HStack(spacing: 12) {
            Text("诵经")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                importRequested = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .accessibilityIdentifier("chantImportButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func importFiles(_ urls: [URL]) {
        var imported: [ChantBook] = []
        var errors: [String] = []
        for url in urls {
            do {
                imported.append(try ChantLibrary.importFile(at: url, context: context))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        importErrors = errors
        if imported.count == 1, let book = imported.first { path.append(book) }
    }
}

struct ChantBookRow: View {
    let book: ChantBook

    var body: some View {
        Text(book.title).lineLimit(2)
    }
}
