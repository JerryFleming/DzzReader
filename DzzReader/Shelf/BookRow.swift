import SwiftUI

struct BookRow: View {
    let book: Book
    var showsChapter: Bool = false

    private var titleLine: String {
        if let number = book.canonNumber { return "\(number) · \(book.title)" }
        return book.title
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let n = book.juanCount { parts.append("\(n)卷") }
        if let a = book.author, !a.isEmpty { parts.append(a) }
        if showsChapter, let progress = book.progress {
            let chapters = book.chapters
            if chapters.indices.contains(progress.chapterIndex) {
                parts.append(chapters[progress.chapterIndex].title)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titleLine)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let progress = book.progress {
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
