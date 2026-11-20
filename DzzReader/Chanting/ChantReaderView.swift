import SwiftData
import SwiftUI
import DzzCore

/// Reads a chanting text: each character with its pinyin above it, row by row as printed in the source,
/// titles in red and subtitles in violet. Always opens at the start.
///
/// Auto-scroll highlights one character-and-pinyin block at a time at the chosen speed (blocks per minute)
/// and keeps the highlighted line in the middle of the screen, except near the start and end of the text.
struct ChantReaderView: View {
    let book: ChantBook
    let settings: ReaderSettings

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("chant.fontSize") private var fontSize = ChantReaderView.defaultFontSize
    /// "light" or "dark" once toggled here; empty follows the 书架 reader's appearance setting.
    @AppStorage("chant.theme") private var chantTheme = ""
    /// Auto-scroll speed in blocks (characters with pinyin) per minute.
    @AppStorage("chant.autoSpeed") private var autoSpeed = ChantReaderView.defaultAutoSpeed

    @State private var document: ChantDocument?
    @State private var error: String?
    @State private var topRow: Int?
    @State private var showChrome = false
    @State private var showContents = false
    @State private var units: ChantUnits?
    /// Auto-scroll is on (it pauses while the chrome shows).
    @State private var autoScrolling = false
    /// Global index of the highlighted block.
    @State private var highlight: Int?

    static let defaultFontSize = 22.0
    static let fontSizeRange: ClosedRange<Double> = 16...40
    static let defaultAutoSpeed = 120.0
    static let autoSpeedRange: ClosedRange<Double> = 20...300

    private var isAutoScrollRunning: Bool { autoScrolling && !showChrome }

    private var theme: Theme { Theme(rawValue: chantTheme) ?? settings.theme }
    private var isDark: Bool { theme.resolved(for: scheme).isDark }
    private var background: Color { Color(theme.background(for: scheme)) }
    private var palette: ChantPalette {
        ChantPalette(foreground: Color(theme.foreground(for: scheme)), dark: theme.resolved(for: scheme).isDark)
    }

    private var passageTitle: String {
        guard let document, let row = document.titleRow(atOrBefore: topRow ?? 0) else { return "" }
        return row.text
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if let error {
                ContentUnavailableView("无法打开", systemImage: "text.book.closed", description: Text(error))
            } else if let document, let units {
                text(document, units)
            } else {
                ProgressView()
            }
            if showChrome && document != nil {
                chrome
            }
        }
        .environment(\.colorScheme, theme.chromeScheme(for: scheme))
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!showChrome)
        .task { await load() }
        // Step the highlight while auto-scroll runs; the task restarts when it pauses or resumes.
        .task(id: isAutoScrollRunning) {
            guard isAutoScrollRunning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 / autoSpeed))
                if Task.isCancelled { break }
                advanceHighlight()
            }
        }
        // Keep the screen awake only while the highlight moves by itself.
        .onChange(of: isAutoScrollRunning, initial: true) { UIApplication.shared.isIdleTimerDisabled = isAutoScrollRunning }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showContents) { contents }
    }

    private func text(_ document: ChantDocument, _ units: ChantUnits) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.5) {
                    ForEach(document.rows) { row in
                        let base = units.starts[row.id]
                        let blocks = units.rows[row.id]
                        // Only the row holding the highlight gets it, so the others are left alone as it moves.
                        let local = highlight.flatMap { $0 >= base && $0 < base + blocks.count ? $0 - base : nil }
                        ChantRowView(row: row, blocks: blocks, baseIndex: base, highlight: local,
                                     fontSize: fontSize, fontFamily: settings.fontName, palette: palette)
                            .padding(.top, row.startsPassage && row.id > 0 ? fontSize * 0.8 : 0)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, settings.margin)
                .padding(.vertical, 24)
            }
            .onChange(of: highlight) {
                // Centre the highlighted line; the scroll view stops at the ends, so the first and last
                // lines stay where they are. Within a line the centre does not move, so nothing scrolls.
                guard let highlight else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(ChantBlockID(index: highlight), anchor: .center)
                }
            }
        }
        .scrollPosition(id: $topRow, anchor: .top)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
        // Keep the status-bar band clear of scrolling text.
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0).background(background, ignoresSafeAreaEdges: .top)
        }
        .onChange(of: fontSize) {
            // Rows reflow; stay on the same one.
            let row = topRow
            DispatchQueue.main.async { topRow = row }
        }
        .accessibilityIdentifier("chantText")
        // Where the highlight is, for UI tests and VoiceOver users following along.
        .overlay(alignment: .bottomTrailing) {
            if let highlight {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(highlight)")
                    .accessibilityIdentifier("chantHighlight")
            }
        }
    }

    // MARK: Auto-scroll

    /// Starts from the highlight if it is still at or below the top of the screen, else from the top row.
    private func startAutoScroll() {
        guard let units else { return }
        let top = topRow ?? 0
        if highlight.map({ units.row(of: $0) < top }) ?? true {
            highlight = units.firstStop(inOrAfterRow: top)
        }
        guard highlight != nil else { return }
        autoScrolling = true
        withAnimation(.easeInOut(duration: 0.2)) { showChrome = false }
    }

    private func stopAutoScroll() {
        autoScrolling = false
        highlight = nil
    }

    private func advanceHighlight() {
        guard let units, let current = highlight else { return }
        if let next = units.stop(after: current) {
            highlight = next
        } else {
            autoScrolling = false          // end of the text: leave the last block highlighted
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                }
                .accessibilityLabel("返回")
                .accessibilityIdentifier("chantBackButton")
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(passageTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("chantPassageTitle")
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)

            Spacer()

            VStack(spacing: 10) {
            if autoScrolling {
                autoScrollSpeedRow
            }
            HStack {
                Button { showContents = true } label: { Label("目录", systemImage: "list.bullet") }
                    .accessibilityIdentifier("chantContentsButton")
                Spacer()
                Button { fontSize = max(Self.fontSizeRange.lowerBound, fontSize - 2) } label: {
                    Label("缩小字号", systemImage: "textformat.size.smaller")
                }
                .disabled(fontSize <= Self.fontSizeRange.lowerBound)
                .accessibilityIdentifier("chantSmallerButton")
                Spacer()
                Button { fontSize = min(Self.fontSizeRange.upperBound, fontSize + 2) } label: {
                    Label("放大字号", systemImage: "textformat.size.larger")
                }
                .disabled(fontSize >= Self.fontSizeRange.upperBound)
                .accessibilityIdentifier("chantLargerButton")
                Spacer()
                Button { chantTheme = isDark ? Theme.light.rawValue : Theme.dark.rawValue } label: {
                    Label(isDark ? "浅色" : "深色", systemImage: isDark ? "sun.max" : "moon")
                }
                .accessibilityIdentifier("chantThemeButton")
                Spacer()
                Button {
                    if autoScrolling { stopAutoScroll() } else { startAutoScroll() }
                } label: {
                    Label(autoScrolling ? "停止自动滚动" : "自动滚动",
                          systemImage: autoScrolling ? "stop.circle" : "play.circle")
                }
                .accessibilityIdentifier("chantAutoScrollButton")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)
            .background(.bar)
        }
        .transition(.opacity)
    }

    private var autoScrollSpeedRow: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Image(systemName: "tortoise")
                Slider(value: $autoSpeed, in: Self.autoSpeedRange, step: 10)
                    .accessibilityIdentifier("chantAutoSpeedSlider")
                Image(systemName: "hare")
                Text("\(Int(autoSpeed))字/分")
                    .font(.caption).monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
                    .accessibilityIdentifier("chantAutoSpeedLabel")
            }
            .foregroundStyle(.secondary)
            Text("自动滚动已暂停 · 轻点屏幕中央继续")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var contents: some View {
        NavigationStack {
            List(document?.titleRows ?? []) { row in
                Button {
                    topRow = row.id
                    if autoScrolling { highlight = units?.firstStop(inOrAfterRow: row.id) }
                    showContents = false
                    showChrome = false
                } label: {
                    HStack {
                        Text(row.text).foregroundStyle(.primary)
                        Spacer()
                        if row.id == document?.titleRow(atOrBefore: topRow ?? 0)?.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { showContents = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Loading

    private func load() async {
        guard document == nil else { return }
        do {
            let loaded = try await ChantLibrary.load(book)
            units = ChantUnits(loaded)
            document = loaded
            topRow = 0
            book.lastOpened = .now      // for 最近阅读
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Colours for the three passage styles and parenthesised notes, after the source PDF
/// (red #C00000, violet #7030A0, dark blue #002060), lightened for dark themes.
struct ChantPalette {
    let foreground: Color
    let dark: Bool

    func text(_ style: ChantStyle) -> Color {
        switch style {
        case .normal: foreground
        case .title: dark ? Color(red: 1, green: 0.45, blue: 0.42) : Color(red: 0.75, green: 0, blue: 0)
        case .subtitle: dark ? Color(red: 0.78, green: 0.6, blue: 0.95) : Color(red: 0.44, green: 0.19, blue: 0.63)
        }
    }

    /// Behind the block auto-scroll is on.
    var highlight: Color {
        dark ? Color(red: 1, green: 0.8, blue: 0.3).opacity(0.3) : Color(red: 1, green: 0.8, blue: 0.2).opacity(0.45)
    }

    var annotation: Color {
        dark ? Color(red: 0.55, green: 0.66, blue: 0.92) : Color(red: 0, green: 0.13, blue: 0.38)
    }
}

/// One printed row: characters with pinyin above, wrapping when the screen is narrower than the source page.
struct ChantRowView: View {
    let row: ChantRow
    /// The row's blocks (`ChantUnits.rows`), their global index, and which one is highlighted.
    let blocks: [ChantCell]
    let baseIndex: Int
    let highlight: Int?
    let fontSize: Double
    let fontFamily: String
    let palette: ChantPalette

    private var scale: Double {
        switch row.style {
        case .normal: 1
        case .subtitle: 1.08
        case .title: 1.3
        }
    }

    private func font(_ size: Double) -> Font {
        fontFamily.isEmpty ? .system(size: size) : .custom(fontFamily, size: size)
    }

    var body: some View {
        let charSize = fontSize * scale
        let pinyinSize = fontSize * 0.5
        let color = palette.text(row.style)
        ChantFlowLayout(centered: row.style != .normal, spacing: fontSize * 0.08, lineSpacing: fontSize * 0.35) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, cell in
                VStack(spacing: 0) {
                    // An empty pinyin line still takes its height, so rows keep one baseline.
                    Text(cell.pinyin.isEmpty ? " " : cell.pinyin)
                        .font(.system(size: pinyinSize))
                        .foregroundStyle(color.opacity(0.75))
                        .lineLimit(1)
                        .fixedSize()
                    Text(cell.char)
                        .font(font(cell.isAnnotation ? charSize * 0.62 : charSize))
                        .foregroundStyle(cell.isAnnotation ? palette.annotation : color)
                        .fixedSize()
                }
                .background {
                    if i == highlight {
                        RoundedRectangle(cornerRadius: fontSize * 0.2)
                            .fill(palette.highlight)
                            .padding(-fontSize * 0.08)
                    }
                }
                .id(ChantBlockID(index: baseIndex + i))
            }
        }
        .frame(maxWidth: .infinity, alignment: row.style == .normal ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.text)
        .accessibilityValue(row.cells.map(\.pinyin).filter { !$0.isEmpty }.joined(separator: " "))
        .accessibilityAddTraits(row.style == .title ? .isHeader : [])
        .accessibilityIdentifier("chantRow-\(row.id)")
    }
}

/// Lays children out left to right, wrapping onto new lines; children in a line share a bottom edge.
struct ChantFlowLayout: Layout {
    var centered = false
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(maxWidth: CGFloat, sizes: [CGSize]) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (i, size) in sizes.enumerated() {
            let added = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if added > maxWidth && !line.indices.isEmpty {
                lines.append(line)
                line = Line()
                line.width = size.width
            } else {
                line.width = added
            }
            line.indices.append(i)
            line.height = max(line.height, size.height)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let lines = lines(maxWidth: maxWidth, sizes: sizes)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for line in lines(maxWidth: bounds.width, sizes: sizes) {
            var x = bounds.minX + (centered ? max(0, (bounds.width - line.width) / 2) : 0)
            for i in line.indices {
                let size = sizes[i]
                subviews[i].place(at: CGPoint(x: x, y: y + line.height - size.height), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
