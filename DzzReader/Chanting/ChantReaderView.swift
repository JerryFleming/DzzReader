import SwiftData
import SwiftUI
import DzzCore

/// Reads a chanting text: each character with its pinyin above it, row by row as printed in the source,
/// titles in red and subtitles in violet, verses centred. Always opens at the start.
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
    /// Show the text converted to the other script (繁 ⇄ 简) from the one it is written in.
    @AppStorage("chant.convertScript") private var convertScript = false

    /// The text as stored, and the script it is mostly written in.
    @State private var source: ChantDocument?
    @State private var sourceScript = ChineseScript.simplified
    /// The text on screen: `source`, or `source` converted to the other script.
    @State private var document: ChantDocument?
    @State private var error: String?
    /// First row mostly on screen; read from the scroll view, never written back to it.
    @State private var topRow: Int?
    /// A row to bring to the top of the screen (目录). A new value each time, so the same row can be asked for twice.
    @State private var jump: ChantJump?
    /// Where rows, their lines and the visible area are, for placing the highlight. Not observed.
    @State private var geometry = ChantGeometry()
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
        .onChange(of: convertScript) { showConverted() }
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
                                     fontSize: fontSize, fontFamily: settings.fontName, palette: palette,
                                     geometry: geometry)
                            .padding(.top, row.startsPassage && row.id > 0 ? fontSize * 0.8 : 0)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, settings.margin)
                .padding(.vertical, 24)
                .coordinateSpace(.named(ChantGeometry.space))
            }
            .onScrollGeometryChange(for: ChantGeometry.Visible.self) {
                ChantGeometry.Visible(top: $0.contentOffset.y + $0.contentInsets.top,
                                      bottom: $0.contentOffset.y + $0.containerSize.height - $0.contentInsets.bottom)
            } action: { _, visible in
                geometry.visible = visible
            }
            // Read which rows are on screen rather than binding a scroll position: a bound position is not
            // updated by `scrollTo`, and SwiftUI re-applies the stale value whenever lazy rows re-measure,
            // which threw the text back to an old place during auto-scroll.
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { visible in
                if let first = visible.min() { topRow = first }
            }
            .onChange(of: jump) {
                guard let jump else { return }
                proxy.scrollTo(jump.row, anchor: .top)
            }
            .onChange(of: fontSize) {
                // Rows reflow; stay on the same one (auto-scroll re-centres the highlight on its next step).
                guard let row = topRow else { return }
                DispatchQueue.main.async { proxy.scrollTo(row, anchor: .top) }
            }
            .onChange(of: highlight) {
                // Scroll only once the highlighted line passes the middle of the screen (or is off screen), then
                // keep it there. The highlight starts at the top of the screen, so starting does not move the text;
                // the scroll view stops at the end, so the last lines stay where they are.
                guard let highlight else { return }
                if let line = geometry.line(of: highlight, units), let visible = geometry.visible,
                   line.minY >= visible.top, line.maxY <= visible.bottom,
                   line.midY <= (visible.top + visible.bottom) / 2 + 1 {
                    return
                }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(ChantBlockID(index: highlight), anchor: .center)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
        // Keep the status-bar band clear of scrolling text.
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0).background(background, ignoresSafeAreaEdges: .top)
        }
        .accessibilityIdentifier("chantText")
        // Where the highlight is, for UI tests and VoiceOver users following along.
        .overlay(alignment: .bottomTrailing) {
            if let highlight {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(highlight)")
                    .accessibilityValue("\(units.row(of: highlight))")
                    .accessibilityIdentifier("chantHighlight")
            }
        }
    }

    // MARK: Auto-scroll

    /// Starts from the first block wholly on screen.
    private func startAutoScroll() {
        guard let units else { return }
        let top = topRow ?? 0
        highlight = geometry.firstStopOnScreen(fromRow: top, units) ?? units.firstStop(inOrAfterRow: top)
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
                Button { convertScript.toggle() } label: {
                    // Names the script a tap switches to.
                    let target = shownScript.other
                    Label {
                        Text(target == .traditional ? "转为繁体" : "转为简体")
                    } icon: {
                        Text(target == .traditional ? "繁" : "简").font(.title3.weight(.medium))
                    }
                }
                .disabled(source == nil)
                .accessibilityIdentifier("chantScriptButton")
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
                    // Bring the passage to the top: the lazy stack has not built far-off rows, so scrolling straight
                    // to a block inside one does nothing. The highlight then moves down from the top as usual.
                    jump = ChantJump(row: row.id)
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

    // MARK: Script

    private var shownScript: ChineseScript { convertScript ? sourceScript.other : sourceScript }

    /// Swaps in the text in the chosen script. It is converted even when shown in its own script, so the
    /// other script's characters mixed into it (南無, 囉 in a simplified text) match the rest. Rows and blocks match one for one, so the reading position,
    /// the highlight and auto-scroll carry on where they were.
    private func showConverted() {
        guard let source else { return }
        let shown = source.converted(to: shownScript)
        units = ChantUnits(shown)
        document = shown
    }

    // MARK: Loading

    private func load() async {
        guard document == nil else { return }
        do {
            let loaded = try await ChantLibrary.load(book)
            let script = ChineseScript.detect(loaded.rows.map(\.text).joined())
            let shown = loaded.converted(to: convertScript ? script.other : script)
            source = loaded
            sourceScript = script
            units = ChantUnits(shown)
            document = shown
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
        case .normal, .verse: foreground
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
    let geometry: ChantGeometry

    private var scale: Double {
        switch row.style {
        case .normal, .verse: 1
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
        ChantFlowLayout(centered: row.style != .normal, spacing: fontSize * 0.08, lineSpacing: fontSize * 0.35,
                        minSlotWidth: row.style == .verse ? charSize * 1.5 : 0,
                        onLines: { geometry.lines[row.id] = $0 }) {
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
        // In content coordinates this changes only when rows lay out again, not while scrolling.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(ChantGeometry.space)).minY } action: {
            geometry.rowTops[row.id] = $0
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
    /// Each child sits centred in a slot at least this wide, at its natural size (nothing is stretched). Verse rows
    /// use 1.5 character widths, so lines with the same number of characters come out the same width whatever
    /// their pinyin. When a row would not fit on one line, every slot shrinks by the same amount (never below a
    /// child's natural width), so a verse line stays on one line and stays balanced.
    var minSlotWidth: CGFloat = 0
    /// Told where each line goes when the layout places its children.
    var onLines: (@Sendable ([ChantLine]) -> Void)? = nil

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

    /// Slot sizes: each child's natural size, widened to the minimum slot width that lets the row fit.
    private func slots(_ sizes: [CGSize], maxWidth: CGFloat) -> [CGSize] {
        guard minSlotWidth > 0, !sizes.isEmpty else { return sizes }
        let fit = (maxWidth - spacing * CGFloat(sizes.count - 1)) / CGFloat(sizes.count)
        let slot = min(minSlotWidth, fit)
        return sizes.map { CGSize(width: max($0.width, slot), height: $0.height) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = slots(subviews.map { $0.sizeThatFits(.unspecified) }, maxWidth: maxWidth)
        let lines = lines(maxWidth: maxWidth, sizes: sizes)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let natural = subviews.map { $0.sizeThatFits(.unspecified) }
        let sizes = slots(natural, maxWidth: bounds.width)
        var y = bounds.minY
        var placed: [ChantLine] = []
        for line in lines(maxWidth: bounds.width, sizes: sizes) {
            placed.append(ChantLine(first: line.indices.first ?? 0, y: y - bounds.minY, height: line.height))
            var x = bounds.minX + (centered ? max(0, (bounds.width - line.width) / 2) : 0)
            for i in line.indices {
                let size = natural[i]
                let slot = sizes[i].width
                subviews[i].place(at: CGPoint(x: x + (slot - size.width) / 2, y: y + line.height - size.height),
                                  proposal: ProposedViewSize(size))
                x += slot + spacing
            }
            y += line.height + lineSpacing
        }
        onLines?(placed)
    }
}

/// A request to bring a row to the top of the screen.
struct ChantJump: Equatable {
    let row: Int
    let token = UUID()
}

/// A laid-out line of a row: its first block (index within the row) and where it sits in the row.
struct ChantLine: Equatable {
    let first: Int
    let y: CGFloat
    let height: CGFloat
}

/// Where things are in the reader, in the scroll content's coordinates: the top of each built row, the lines
/// of each row, and the visible area. Written by layout and geometry callbacks; read when the highlight
/// starts or moves. A plain reference so that writing it never redraws anything. Only touched on the main
/// thread (layout and view callbacks run there), hence the unchecked conformance.
final class ChantGeometry: @unchecked Sendable {
    static let space = "chantContent"

    struct Visible: Equatable {
        let top: CGFloat
        let bottom: CGFloat
    }

    var rowTops: [Int: CGFloat] = [:]
    var lines: [Int: [ChantLine]] = [:]
    var visible: Visible?

    /// Top and bottom of the line holding block `index`.
    func line(of index: Int, _ units: ChantUnits) -> (minY: CGFloat, midY: CGFloat, maxY: CGFloat)? {
        let row = units.row(of: index)
        guard let top = rowTops[row], let line = lines[row]?.last(where: { $0.first <= index - units.starts[row] })
        else { return nil }
        let minY = top + line.y
        return (minY, minY + line.height / 2, minY + line.height)
    }

    /// The first stop in a line that starts at or below the top of the screen, looking from `row` on.
    func firstStopOnScreen(fromRow row: Int, _ units: ChantUnits) -> Int? {
        guard let visible else { return nil }
        for r in row..<min(row + 50, units.starts.count) {
            guard let top = rowTops[r], let lines = lines[r] else { return nil }
            guard let line = lines.first(where: { top + $0.y >= visible.top - 0.5 }) else { continue }
            guard top + line.y < visible.bottom else { return nil }
            return units.firstStop(atOrAfter: units.starts[r] + line.first)
        }
        return nil
    }
}
