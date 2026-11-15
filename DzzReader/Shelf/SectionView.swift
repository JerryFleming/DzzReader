import SwiftData
import SwiftUI

/// All books in one 部, in 经号 order.
struct SectionView: View {
    let sectionName: String
    @Query private var books: [Book]

    init(sectionName: String) {
        self.sectionName = sectionName
        let name = sectionName
        _books = Query(filter: #Predicate<Book> { $0.section == name }, sort: \Book.catalogOrder)
    }

    var body: some View {
        List(books) { book in
            NavigationLink(value: book) { BookRow(book: book, showsChapter: false) }
        }
        .navigationTitle(sectionName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
