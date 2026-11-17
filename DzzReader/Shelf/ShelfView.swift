import SwiftData
import SwiftUI

/// Root shelf: recents, imported books, and one row per 部.
struct ShelfView: View {
    @Query(sort: \Book.catalogOrder) private var books: [Book]
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
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
        // Nothing here changes structure while typing: the results list is always present (hidden while the
        // query is empty) and the clear button only fades. Inserting or removing views as the first character
        // arrives re-hosts the top bar and drops the search field's focus.
        let searching = !searchText.isEmpty
        shelf
            .accessibilityHidden(searching)   // covered by the results; don't let VoiceOver or tests find rows twice
            .overlay {
                ShelfSearchResults(books: books, query: searchText)
                    .background(Color(.systemGroupedBackground))
                    .opacity(searching ? 1 : 0)
                    .allowsHitTesting(searching)
                    .accessibilityHidden(!searching)
            }
            .scrollDismissesKeyboard(.never)              // only Enter dismisses the keyboard
            .navigationTitle("书架")                       // back-button title on pushed pages
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .onChange(of: searchFocused) { _, focused in
                // Focus can still be taken away by the system mid-search; give it back unless the reader ended
                // the search (Enter, import, opening a book, switching tabs).
                if !focused && keepSearchFocus {
                    DispatchQueue.main.async { if keepSearchFocus { searchFocused = true } }
                }
            }
            .onDisappear { endSearchFocus() }
    }

    /// True from the moment the field gains focus until the reader deliberately ends the search.
    @State private var keepSearchFocus = false

    private func endSearchFocus() {
        keepSearchFocus = false
        searchFocused = false
    }

    /// Search field with the import button beside it, in place of the navigation bar.
    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索经名或经号", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { endSearchFocus() }           // Enter is the only key that dismisses
                    .accessibilityIdentifier("shelfSearchField")
                    .accessibilityAddTraits(.isSearchField)
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.secondary)
                .opacity(searchText.isEmpty ? 0 : 1)
                .disabled(searchText.isEmpty)
                .accessibilityLabel("清除")
                .accessibilityHidden(searchText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { searchFocused = true }
            .onChange(of: searchFocused) { _, focused in
                if focused { keepSearchFocus = true }
            }

            Button {
                endSearchFocus()
                importRequested = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
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
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.name)
                            if let range = CatalogLoader.bundledSections[section.name] {
                                Text(String(format: "%04d-%04d", range.firstNumber, range.lastNumber))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .accessibilityIdentifier("section-range-\(section.name)")
                            }
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
