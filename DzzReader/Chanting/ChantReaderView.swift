import SwiftData
import SwiftUI
import DzzCore

/// Reads a chanting text: each character with its pinyin above it, row by row as printed in the source,
/// titles in red and subtitles in violet. The row at the top of the screen is remembered.
struct ChantReaderView: View {
    let book: ChantBook
    let settings: ReaderSettings

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("chant.fontSize") private var fontSize = ChantReaderView.defaultFontSize

    @State private var document: ChantDocument?
    @State private var error: String?
    @State private var topRow: Int?
    @State private var showChrome = false
    @State private var showContents = false

    static let defaultFontSize = 22.0
    static let fontSizeRange: ClosedRange<Double> = 16...40

    private var theme: Theme { settings.theme }
    private var background: Color { Color(theme.background(for: scheme)) }
    private var palette: ChantPalette {
        ChantPalette(foreground: Color(theme.foreground(for: scheme)), dark: theme.resolved(for: scheme).isDark)
    }

    private var fraction: Double {
        guard let document, document.rows.count > 1 else { return 0 }
        return Double(min(topRow ?? 0, document.rows.count - 1)) / Double(document.rows.count - 1)
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
            } else if let document {
                text(document)
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
        .onDisappear { saveProgress() }
        .onChange(of: scenePhase) { if scenePhase != .active { saveProgress() } }
        .onChange(of: showChrome) { if showChrome { saveProgress() } }
        .sheet(isPresented: $showContents) { contents }
    }

    private func text(_ document: ChantDocument) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.5) {
                ForEach(document.rows) { row in
                    ChantRowView(row: row, fontSize: fontSize, fontFamily: settings.fontName, palette: palette)
                        .padding(.top, row.startsPassage && row.id > 0 ? fontSize * 0.8 : 0)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, settings.margin)
            .padding(.vertical, 24)
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
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityIdentifier("chantProgressLabel")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
        .transition(.opacity)
    }

    private var contents: some View {
        NavigationStack {
            List(document?.titleRows ?? []) { row in
                Button {
                    topRow = row.id
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

    // MARK: Loading and progress

    private func load() async {
        guard document == nil else { return }
        do {
            let loaded = try await ChantLibrary.load(book)
            document = loaded
            book.lastOpened = .now
            try? context.save()
            let saved = min(max(book.rowIndex, 0), loaded.rows.count - 1)
            if saved > 0 {
                // Let the rows exist before asking the scroll view to go to one.
                try? await Task.sleep(for: .milliseconds(50))
                topRow = saved
            } else {
                topRow = 0
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The scroll position lives in view state while reading and is written to the store only here
    /// (leaving, backgrounding, or opening the chrome), so scrolling never makes the shelves re-fetch.
    private func saveProgress() {
        guard document != nil, let topRow else { return }
        guard book.rowIndex != topRow || book.fraction != fraction else { return }
        book.rowIndex = topRow
        book.fraction = fraction
        try? context.save()
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

    var annotation: Color {
        dark ? Color(red: 0.55, green: 0.66, blue: 0.92) : Color(red: 0, green: 0.13, blue: 0.38)
    }
}

/// One printed row: characters with pinyin above, wrapping when the screen is narrower than the source page.
struct ChantRowView: View {
    let row: ChantRow
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
            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
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
