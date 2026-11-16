import SwiftData
import SwiftUI

struct ReaderView: View {
    @State private var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showChapters = false
    @State private var showAppearance = false
    @State private var showBookmarks = false

    init(book: Book, context: ModelContext, settings: ReaderSettings) {
        _vm = State(initialValue: ReaderViewModel(book: book, context: context, settings: settings))
    }

    private var theme: Theme { vm.settings.theme }

    var body: some View {
        ZStack {
            Color(theme.background(for: scheme)).ignoresSafeArea()

            if let error = vm.error {
                ContentUnavailableView("无法打开", systemImage: "book.closed", description: Text(error))
            } else if vm.loaded == nil {
                ProgressView()
            } else {
                ChapterTextView(
                    attributedText: vm.attributed,
                    contentID: vm.contentID,
                    backgroundColor: theme.background(for: scheme),
                    tintColor: theme.foreground(for: scheme).withAlphaComponent(0.8),
                    margin: vm.settings.margin,
                    scrollTarget: $vm.scrollTarget,
                    autoScrollSpeed: vm.autoScrolling && !vm.showChrome ? vm.settings.autoScrollSpeed : nil,
                    onVisibleOffsetChanged: { vm.recordVisibleRenderedOffset($0) },
                    onNextChapter: { vm.next() },
                    onAddBookmark: { range, text in
                        let source = vm.rendered?.sourceOffset(forRendered: range.location) ?? 0
                        vm.addBookmark(sourceOffset: source, excerpt: text)
                    },
                    onTapCenter: { withAnimation(.easeInOut(duration: 0.2)) { vm.showChrome.toggle() } },
                    onReachedEnd: {
                        if vm.hasNext {
                            vm.next()
                        } else if vm.autoScrolling {
                            vm.autoScrolling = false
                            vm.toast = "已读完"
                        }
                    }
                )
                .ignoresSafeArea()
                .accessibilityIdentifier("chapterText")
            }

            // Keep the status-bar and home-indicator bands clear of scrolling text.
            VStack {
                Color(theme.background(for: scheme)).frame(height: windowSafeArea.top)
                Spacer()
                Color(theme.background(for: scheme)).frame(height: windowSafeArea.bottom)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if vm.showChrome && vm.loaded != nil {
                chrome
            }

            if let toast = vm.toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityIdentifier("toast")
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { vm.toast = nil }
                    }
            }
        }
        .environment(\.colorScheme, theme.chromeScheme(for: scheme))
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!vm.showChrome)
        .task { await vm.load(scheme: scheme) }
        .onChange(of: vm.settings.snapshot) { vm.restyle(scheme: scheme) }
        .onChange(of: scheme) { vm.restyle(scheme: scheme) }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showChapters) { ChapterListSheet(vm: vm) }
        .sheet(isPresented: $showAppearance) {
            AppearanceSheet(settings: vm.settings)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBookmarks) { BookmarkListSheet(vm: vm) }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                }
                .accessibilityLabel("返回")
                .accessibilityIdentifier("backButton")
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(vm.chapterTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("chapterTitle")
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .padding(.top, windowSafeArea.top)
            .background(.bar)

            Spacer()

            VStack(spacing: 10) {
                if vm.autoScrolling {
                    autoScrollSpeedRow
                }
                ProgressSliderBar(vm: vm)
                HStack {
                    Button { showChapters = true } label: { Label("目录", systemImage: "list.bullet") }
                        .accessibilityIdentifier("chaptersButton")
                    Spacer()
                    Button { vm.addBookmark(sourceOffset: vm.visibleSourceOffset, excerpt: nil) } label: {
                        Label("书签", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("bookmarkButton")
                    Spacer()
                    Button { showBookmarks = true } label: { Label("书签列表", systemImage: "bookmark.fill") }
                        .accessibilityIdentifier("bookmarkListButton")
                    Spacer()
                    Button {
                        vm.autoScrolling.toggle()
                        if vm.autoScrolling {
                            withAnimation(.easeInOut(duration: 0.2)) { vm.showChrome = false }
                        }
                    } label: {
                        Label(vm.autoScrolling ? "停止自动滚动" : "自动滚动",
                              systemImage: vm.autoScrolling ? "stop.circle" : "play.circle")
                    }
                    .accessibilityIdentifier("autoScrollButton")
                    Spacer()
                    Button { showAppearance = true } label: { Label("外观", systemImage: "textformat.size") }
                        .accessibilityIdentifier("appearanceButton")
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .padding(.horizontal, 24)
            }
            .padding(.top, 12).padding(.bottom, 8 + windowSafeArea.bottom)
            .background(.bar)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private var autoScrollSpeedRow: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Image(systemName: "tortoise")
                Slider(value: Bindable(vm.settings).autoScrollSpeed, in: ReaderSettings.autoScrollSpeedRange, step: 5)
                    .accessibilityIdentifier("autoScrollSpeedSlider")
                Image(systemName: "hare")
                Text("\(Int(vm.settings.autoScrollSpeed))")
                    .font(.caption).monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
                    .accessibilityIdentifier("autoScrollSpeedLabel")
            }
            .foregroundStyle(.secondary)
            Text("自动滚动已暂停 · 轻点屏幕中央继续")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    /// Insets of the key window (status bar / home indicator), independent of the hidden navigation bar.
    private var windowSafeArea: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

/// Previous/next buttons flanking a whole-book slider. (Full behaviour lands in Task 9.)
struct ProgressSliderBar: View {
    @Bindable var vm: ReaderViewModel
    @State private var value = 0.0
    @State private var editing = false

    var body: some View {
        VStack(spacing: 4) {
            if editing {
                Text("\(vm.preview(fraction: value)) · \(Int((value * 100).rounded()))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { vm.previous() } label: { Image(systemName: "chevron.left") }
                    .disabled(!vm.hasPrevious)
                    .accessibilityIdentifier("previousChapter")
                Slider(value: $value, in: 0...1) { isEditing in
                    editing = isEditing
                    if !isEditing { vm.go(toFraction: value) }
                }
                .accessibilityIdentifier("progressSlider")
                Button { vm.next() } label: { Image(systemName: "chevron.right") }
                    .disabled(!vm.hasNext)
                    .accessibilityIdentifier("nextChapter")
                Text("\(vm.chapterIndex + 1)/\(max(vm.chapters.count, 1)) · \(Int((vm.fraction * 100).rounded()))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .trailing)
                    .accessibilityIdentifier("progressLabel")
            }
            .padding(.horizontal, 16)
        }
        .onAppear { value = vm.fraction }
        .onChange(of: vm.fraction) { if !editing { value = vm.fraction } }
    }
}
