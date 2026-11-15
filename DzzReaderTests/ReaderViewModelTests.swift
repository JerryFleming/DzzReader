import Foundation
import SwiftData
import SwiftUI
import Testing
import DzzCore
@testable import DzzReader

@Suite @MainActor struct ReaderViewModelTests {
    /// The container must outlive the test or SwiftData destroys the models.
    private func makeVM() async throws -> (ReaderViewModel, ModelContext, ModelContainer) {
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
        let vm = ReaderViewModel(book: book, context: context, settings: settings)
        await vm.load(fileURL: fixture, scheme: .light)
        return (vm, context, container)
    }

    @Test func bookmarkFromPositionUsesFollowingText() async throws {
        let (vm, context, container) = try await makeVM()
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

    @Test func bookmarkFromSelectionKeepsSelectedText() async throws {
        let (vm, context, container) = try await makeVM()
        defer { _ = container }
        vm.go(toChapter: 2, sourceOffset: 10)
        vm.addBookmark(sourceOffset: 10, excerpt: "　　如是我闻。一时")
        let mark = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(mark.excerpt == "如是我闻。一时")
        #expect(mark.chapterIndex == 2 && mark.characterOffset == 10)
    }

    @Test func jumpAndDelete() async throws {
        let (vm, context, container) = try await makeVM()
        defer { _ = container }
        vm.go(toChapter: 3, sourceOffset: 42)
        vm.addBookmark(sourceOffset: 42, excerpt: nil)
        vm.go(toChapter: 0)
        let mark = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        vm.jump(to: mark)
        #expect(vm.chapterIndex == 3)
        #expect(vm.visibleSourceOffset == 42)
        #expect(vm.scrollTarget == vm.rendered?.renderedOffset(forSource: 42))
        vm.delete(mark)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }

    @Test func currentSectionFollowsVisibleOffset() async throws {
        let (vm, _, container) = try await makeVM()
        defer { _ = container }
        let chapter = vm.chapters[2]
        #expect(chapter.sections.count == 2)
        vm.go(toChapter: 2, sourceOffset: 0)
        #expect(vm.currentSectionIndex == nil)
        vm.go(toChapter: 2, sourceOffset: chapter.sections[1].offset - chapter.startOffset + 5)
        #expect(vm.currentSectionIndex == 1)
    }

    @Test func fractionJumpLandsInExpectedChapter() async throws {
        let (vm, _, container) = try await makeVM()
        defer { _ = container }
        vm.go(toFraction: 1.0)
        #expect(vm.chapterIndex == vm.chapters.count - 1)
        #expect(vm.fraction == 1.0)
        vm.go(toFraction: 0)
        #expect(vm.chapterIndex == 0 && vm.visibleSourceOffset == 0)
    }
}
