import SwiftData
import SwiftUI

/// Minimal placeholders so the reader compiles; Task 9 replaces these with the real sheets.
struct ChapterListSheet: View {
    let vm: ReaderViewModel
    var body: some View { Text("目录") }
}

struct AppearanceSheet: View {
    let settings: ReaderSettings
    var body: some View { Text("外观") }
}

struct BookmarkListSheet: View {
    let vm: ReaderViewModel
    var body: some View { Text("书签") }
}
