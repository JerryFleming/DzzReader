import SwiftData
import SwiftUI
import UIKit

// MARK: - Chapter list

struct ChapterListSheet: View {
    let vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(vm.chapters.indices, id: \.self) { index in
                        let chapter = vm.chapters[index]
                        let isCurrent = index == vm.chapterIndex
                        Button {
                            vm.go(toChapter: index)
                            dismiss()
                        } label: {
                            HStack {
                                Text(chapter.title)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isCurrent { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .id(index)
                        .accessibilityIdentifier("chapter-\(index)")

                        ForEach(chapter.sections.indices, id: \.self) { s in
                            let section = chapter.sections[s]
                            let isCurrentSection = isCurrent && vm.currentSectionIndex == s
                            Button {
                                vm.go(toChapter: index, sourceOffset: section.offset - chapter.startOffset)
                                dismiss()
                            } label: {
                                Text(section.title)
                                    .font(.subheadline)
                                    .fontWeight(isCurrentSection ? .semibold : .regular)
                                    .foregroundStyle(isCurrentSection ? .primary : .secondary)
                                    .padding(.leading, 20)
                            }
                            .accessibilityIdentifier("section-\(index)-\(s)")
                        }
                    }
                }
                .listStyle(.plain)
                .onAppear { proxy.scrollTo(vm.chapterIndex, anchor: .center) }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Appearance

struct AppearanceSheet: View {
    @Bindable var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    Picker("主题", selection: $settings.theme) {
                        ForEach(Theme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("字体") {
                    Picker("字体", selection: $settings.fontName) {
                        ForEach(ReaderSettings.curatedFonts, id: \.family) { font in
                            Text(font.name).tag(font.family)
                        }
                        if !ReaderSettings.curatedFonts.contains(where: { $0.family == settings.fontName }) {
                            Text(settings.fontName).tag(settings.fontName)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    NavigationLink("其它字体…") { OtherFontsList(selection: $settings.fontName) }
                }

                Section {
                    HStack {
                        Text("Aa").font(.footnote)
                        Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                            .accessibilityIdentifier("fontSizeSlider")
                        Text("Aa").font(.title2)
                    }
                    Text("\(Int(settings.fontSize)) pt 预览：如是我闻。一时佛在舍卫国。")
                        .font(Font(AttributedChapterBuilder.font(named: settings.fontName, size: settings.fontSize)))
                        .lineLimit(2)
                } header: { Text("字号") }

                Section("行距") {
                    Slider(value: $settings.lineSpacing, in: ReaderSettings.lineSpacingRange, step: 0.1) {
                        Text("行距")
                    } minimumValueLabel: { Image(systemName: "text.alignleft") } maximumValueLabel: { Image(systemName: "text.justify") }
                }

                Section("页边距") {
                    Slider(value: $settings.margin, in: ReaderSettings.marginRange, step: 2) {
                        Text("页边距")
                    } minimumValueLabel: { Image(systemName: "rectangle.compress.vertical") } maximumValueLabel: { Image(systemName: "rectangle.expand.vertical") }
                }

                Section {
                    Toggle("翻屏按钮", isOn: $settings.showPageButtons)
                        .accessibilityIdentifier("pageButtonsToggle")
                } footer: { Text("在阅读界面右下角显示上一屏、下一屏按钮。") }
            }
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

/// Every installed family that can render CJK text.
private struct OtherFontsList: View {
    @Binding var selection: String

    private static let families: [String] = {
        let probe = "佛".unicodeScalars.first!.value
        return UIFont.familyNames.sorted().filter { family in
            guard let font = UIFont(name: family, size: 12),
                  let set = font.fontDescriptor.object(forKey: .characterSet) as? NSCharacterSet else { return false }
            return set.longCharacterIsMember(probe)
        }
    }()

    var body: some View {
        List(Self.families, id: \.self) { family in
            Button {
                selection = family
            } label: {
                HStack {
                    Text(family).font(Font(UIFont(name: family, size: 17) ?? .systemFont(ofSize: 17)))
                    Spacer()
                    if family == selection { Image(systemName: "checkmark") }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("其它字体")
    }
}

// MARK: - Bookmarks

struct BookmarkListSheet: View {
    let vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var bookmarks: [Bookmark]

    init(vm: ReaderViewModel) {
        self.vm = vm
        let id = vm.book.id
        _bookmarks = Query(filter: #Predicate<Bookmark> { $0.book?.id == id }, sort: \Bookmark.createdAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(bookmarks) { mark in
                    Button {
                        vm.jump(to: mark)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mark.excerpt).lineLimit(2).foregroundStyle(.primary)
                            HStack {
                                Text(vm.chapters.indices.contains(mark.chapterIndex) ? vm.chapters[mark.chapterIndex].title : "")
                                Spacer()
                                Text(mark.createdAt, format: .relative(presentation: .named))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { vm.delete(bookmarks[i]) }
                }
            }
            .overlay {
                if bookmarks.isEmpty {
                    ContentUnavailableView("还没有书签", systemImage: "bookmark", description: Text("阅读时点击书签按钮，或选中文字后选择“添加书签”。"))
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
