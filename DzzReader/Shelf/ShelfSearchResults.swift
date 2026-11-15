import SwiftUI

/// Flat list of books whose title contains the query or whose 经号 starts with it.
struct ShelfSearchResults: View {
    let books: [Book]
    let query: String

    private var matches: [Book] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return books.filter { book in
            book.title.localizedStandardContains(q) || (book.canonNumber?.hasPrefix(q) ?? false)
        }
    }

    var body: some View {
        List(matches) { book in
            NavigationLink(value: book) { BookRow(book: book, showsChapter: false) }
        }
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
