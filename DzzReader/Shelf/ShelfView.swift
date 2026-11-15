import SwiftData
import SwiftUI

/// Root shelf: recents, imported books, and one row per 部.
struct ShelfView: View {
    @Query(sort: \Book.catalogOrder) private var books: [Book]
    @State private var searchText = ""
    @Binding var importRequested: Bool

    private var recents: [Book] {
        books.filter { $0.lastOpened != nil }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            .prefix(5).map { $0 }
    }

    private var imported: [Book] {
        books.filter { $0.source == .imported }.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// 部 in toc order (by the smallest 经号 they contain) with their book counts.
    private var sections: [(name: String, count: Int)] {
        var firstOrder: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for book in books where book.source == .bundled {
            let name = book.section ?? "其它"
            counts[name, default: 0] += 1
            firstOrder[name] = min(firstOrder[name] ?? .max, book.catalogOrder)
        }
        return counts.keys.sorted { firstOrder[$0]! < firstOrder[$1]! }.map { ($0, counts[$0]!) }
    }

    var body: some View {
        Group {
            if searchText.isEmpty {
                shelf
            } else {
                ShelfSearchResults(books: books, query: searchText)
            }
        }
        .navigationTitle("大藏经")
        .searchable(text: $searchText, prompt: "搜索经名或经号")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importRequested = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private var shelf: some View {
        List {
            if !recents.isEmpty {
                Section("最近阅读") {
                    ForEach(recents) { book in
                        NavigationLink(value: book) { BookRow(book: book, showsChapter: true) }
                    }
                }
            }
            if !imported.isEmpty {
                Section("导入的书") {
                    ForEach(imported) { book in
                        NavigationLink(value: book) { BookRow(book: book, showsChapter: false) }
                    }
                    .onDelete(perform: deleteImported)
                }
            }
            Section {
                ForEach(sections, id: \.name) { section in
                    NavigationLink(value: ShelfSection(name: section.name)) {
                        HStack {
                            Text(section.name)
                            Spacer()
                            Text("\(section.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    @Environment(\.modelContext) private var context

    private func deleteImported(at offsets: IndexSet) {
        for index in offsets {
            try? Importer.delete(imported[index], context: context)
        }
    }
}

/// Navigation value for a 部 row.
struct ShelfSection: Hashable {
    let name: String
}
