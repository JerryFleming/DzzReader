import Foundation
import SwiftData
import SwiftUI
import Testing
import DzzCore
@testable import DzzReader

@Suite @MainActor struct ReaderViewModelTests {
    /// The container must outlive the test or SwiftData destroys the models.
    private func makeVM(wholeBook: Bool = true) async throws -> (ReaderViewModel, ModelContext, ModelContainer) {
        let container = try ModelContainer.inMemory()
        let context = container.mainContext
        let fixture = TestFixtures.root.appending(path: "marked-3juan.txt")
        let size = try FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as! Int
        let book = Book(id: "T0001", title: "长阿含经", source: .bundled, relativePath: "x", section: nil, juanCount: 22,
                        author: nil, catalogOrder: 0, byteSize: size, encodingName: "utf-8")
        context.insert(book)
        let loaded = try await BookLoader.load(book: book, fileURL: fixture)
        _ = loaded
        let settings = ReaderSettings(defaults: UserDefaults(suiteName: "ReaderViewModelTests-\(UUID().uuidString)")!)
        let vm = ReaderViewModel(book: book, context: context, settings: settings, wholeBookLimit: wholeBook ? .max : 0)
        await vm.load(fileURL: fixture, scheme: .light)
        return (vm, context, container)
    }

    @Test(arguments: [true, false]) func bookmarkFromPositionUsesFollowingText(wholeBook: Bool) async throws {
        let (vm, context, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        vm.go(toChapter: 1, sourceOffset: 0)
        vm.addBookmark(sourceOffset: 0, excerpt: nil)
        let marks = try context.fetch(FetchDescriptor<Bookmark>())
        #expect(marks.count == 1)
        #expect(marks.first?.chapterIndex == 1)
        #expect(marks.first?.characterOffset == 0)
        #expect(marks.first?.excerpt.hasPrefix("佛说长阿含经卷第一") == true)   // mark prefix and indent stripped
        #expect((marks.first?.excerpt.count ?? 99) <= 40)
        #expect(vm.toast == "已添加书签")
    }

    @Test(arguments: [true, false]) func bookmarkFromSelectionKeepsSelectedText(wholeBook: Bool) async throws {
        let (vm, context, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        vm.go(toChapter: 2, sourceOffset: 10)
        vm.addBookmark(sourceOffset: 10, excerpt: "　　如是我闻。一时")
        let mark = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(mark.excerpt == "如是我闻。一时")
        #expect(mark.chapterIndex == 2 && mark.characterOffset == 10)
    }

    @Test(arguments: [true, false]) func jumpAndDelete(wholeBook: Bool) async throws {
        let (vm, context, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        vm.go(toChapter: 3, sourceOffset: 42)
        vm.addBookmark(sourceOffset: 42, excerpt: nil)
        vm.go(toChapter: 0)
        let mark = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        vm.jump(to: mark)
        #expect(vm.chapterIndex == 3)
        #expect(vm.visibleSourceOffset == 42)
        #expect(vm.scrollTarget == vm.renderedOffset(chapter: 3, sourceOffset: 42))
        vm.delete(mark)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }

    @Test(arguments: [true, false]) func currentSectionFollowsVisibleOffset(wholeBook: Bool) async throws {
        let (vm, _, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        let chapter = vm.chapters[2]
        #expect(chapter.sections.count == 2)
        vm.go(toChapter: 2, sourceOffset: 0)
        #expect(vm.currentSectionIndex == nil)
        vm.go(toChapter: 2, sourceOffset: chapter.sections[1].offset - chapter.startOffset + 5)
        #expect(vm.currentSectionIndex == 1)
    }

    @Test(arguments: [true, false]) func fractionJumpLandsInExpectedChapter(wholeBook: Bool) async throws {
        let (vm, _, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        vm.go(toFraction: 1.0)
        #expect(vm.chapterIndex == vm.chapters.count - 1)
        #expect(vm.fraction == 1.0)
        vm.go(toFraction: 0)
        #expect(vm.chapterIndex == 0 && vm.visibleSourceOffset == 0)
    }

    // MARK: Whole-book documents

    @Test func wholeBookRendersEveryChapterOnce() async throws {
        let (vm, _, container) = try await makeVM(wholeBook: true)
        defer { _ = container }
        #expect(vm.isWholeBook)
        #expect(vm.document == 0..<vm.chapters.count)
        #expect(vm.nextDocumentTitle == nil && vm.previousDocumentTitle == nil)
        #expect(vm.attributed.string.hasSuffix("全书完"))
        let content = vm.contentID
        vm.go(toChapter: 2, sourceOffset: 5)
        vm.next()
        #expect(vm.contentID == content)                // chapter changes only scroll
        #expect(vm.chapterIndex == 3)
        #expect(vm.scrollTarget == vm.rendered?.chapterStarts[3])
    }

    @Test func wholeBookChapterFollowsTheVisibleText() async throws {
        let (vm, context, container) = try await makeVM(wholeBook: true)
        defer { _ = container }
        let starts = try #require(vm.rendered?.chapterStarts)
        vm.recordVisibleRenderedOffset(starts[2] + 7)
        #expect(vm.chapterIndex == 2)
        #expect(vm.renderedOffset(chapter: 2, sourceOffset: vm.visibleSourceOffset) == starts[2] + 7)
        #expect(vm.book.progress?.chapterIndex == 2)
        vm.recordVisibleRenderedOffset(starts[1])
        #expect(vm.chapterIndex == 1)

        // A selection bookmark lands in the chapter of the selection, not the one at the top of the screen.
        vm.addBookmark(renderedOffset: starts[3] + 4, excerpt: "选中")
        let mark = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(mark.chapterIndex == 3)
        #expect(vm.renderedOffset(chapter: 3, sourceOffset: mark.characterOffset) == starts[3] + 4)
    }

    @Test(arguments: [true, false]) func quoteMarkupNamesBookAndChapterOfTheSelection(wholeBook: Bool) async throws {
        let (vm, _, container) = try await makeVM(wholeBook: wholeBook)
        defer { _ = container }
        vm.go(toChapter: 2, sourceOffset: 0)
        let start = vm.renderedOffset(chapter: 2, sourceOffset: 5)
        let markup = vm.quoteMarkup(renderedOffset: start, selection: "　　如是我闻。\n第0章 一时佛|在::舍卫国。")
        #expect(markup == "长阿含经•\(vm.chapters[2].title)::如是我闻。一时佛在：舍卫国。")
        #expect(QuoteScript(markup).source == "长阿含经•\(vm.chapters[2].title)")
    }

    @Test func wholeBookEdgesDoNotChangeDocument() async throws {
        let (vm, _, container) = try await makeVM(wholeBook: true)
        defer { _ = container }
        let content = vm.contentID
        vm.reachedStart()
        vm.reachedEnd()
        #expect(vm.contentID == content)
        vm.autoScrolling = true
        vm.reachedEnd()
        #expect(!vm.autoScrolling && vm.toast == "已读完")
    }

    @Test func autoScrollHoldsBackProgressSavesUntilStopped() async throws {
        let (vm, context, container) = try await makeVM(wholeBook: true)
        defer { _ = container }
        vm.autoScrolling = true
        vm.recordVisibleRenderedOffset(vm.renderedOffset(chapter: 1, sourceOffset: 10))
        vm.recordVisibleRenderedOffset(vm.renderedOffset(chapter: 1, sourceOffset: 60))
        // The second report fell inside the save interval: the reader knows the position, the model doesn't yet
        // (touching the model would make every @Query, such as the shelf's, re-fetch).
        #expect(vm.visibleSourceOffset == 60)
        #expect(vm.book.progress?.characterOffset != 60)
        #expect(!context.hasChanges)
        vm.autoScrolling = false                         // stopping writes and saves it
        #expect(vm.book.progress?.characterOffset == 60)
        #expect(!context.hasChanges)

        vm.recordVisibleRenderedOffset(vm.renderedOffset(chapter: 1, sourceOffset: 90))
        #expect(!context.hasChanges)                     // manual reading saves straight away
    }

    @Test func autoScrollFrameRateFollowsSpeed() {
        let slow = ChapterTextView.Coordinator.frameRateRange(speed: 5, scale: 3)
        #expect(slow.preferred == 15 && slow.maximum == 30)
        let fast = ChapterTextView.Coordinator.frameRateRange(speed: 150, scale: 3)
        #expect(fast.preferred == 30)
        let crawl = ChapterTextView.Coordinator.frameRateRange(speed: 1, scale: 2)
        #expect(crawl.preferred == 10 && crawl.minimum <= 10)
    }

    // MARK: Chapter-at-a-time documents

    @Test func largeBookShowsOneChapterAndPagesAtEdges() async throws {
        let (vm, _, container) = try await makeVM(wholeBook: false)
        defer { _ = container }
        #expect(!vm.isWholeBook)
        vm.go(toChapter: 1)
        #expect(vm.document == 1..<2)
        #expect(vm.nextDocumentTitle == vm.chapters[2].title)
        #expect(vm.previousDocumentTitle == vm.chapters[0].title)

        vm.reachedEnd()
        #expect(vm.document == 2..<3 && vm.chapterIndex == 2 && vm.visibleSourceOffset == 0)

        vm.reachedStart()
        #expect(vm.document == 1..<2 && vm.chapterIndex == 1)
        #expect(vm.visibleSourceOffset == vm.chapters[1].length)   // lands on the previous chapter's last screen

        vm.go(toChapter: vm.chapters.count - 1)
        vm.autoScrolling = true
        vm.reachedEnd()
        #expect(!vm.autoScrolling && vm.toast == "已读完")
    }
}
