import SwiftUI
import UIKit

/// The 诵经 shelf's help sheet: the JSON format `ChantDocument.parse` accepts, and the bundled
/// 佛教念诵集.json to look at as a sample. Keep the text in step with DzzCore/ChantDocument.swift.
struct ChantFormatHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("诵经文本是一个 JSON 数组，按顺序列出每一项。每项是以下三种之一：")
                }
                Section("字") {
                    code(#"{"char": "大", "pinyin": "dà"}"#)
                    Text("一个字及其拼音。标点的拼音留空或省略；char 不能为空。")
                }
                Section("换行") {
                    code(#"{"type": "linebreak"}"#)
                    Text("结束当前一行。连续换行不会产生空行。")
                }
                Section("段落") {
                    code(#"{"type": "passage", "style": "title"}"#)
                    Text("另起一段，此后各行都用这个样式，直到下一个段落项。开头默认为 normal。")
                    style("title", "标题：红色、较大、居中，列入目录")
                    style("subtitle", "副标题：紫色、居中")
                    style("verse", "偈颂：居中，每行一句")
                    style("normal", "正文：左对齐")
                }
                Section("注释") {
                    Text("（…）或 (…) 中的字连同括号视为注释：字号较小、不显示拼音，自动滚动时跳过。")
                }
                Section {
                    code("""
                    [
                      {"type": "passage", "style": "title"},
                      {"char": "心", "pinyin": "xīn"},
                      {"char": "经", "pinyin": "jīng"},
                      {"type": "passage", "style": "normal"},
                      {"char": "观", "pinyin": "guān"},
                      {"char": "（", "pinyin": ""},
                      {"char": "三", "pinyin": ""},
                      {"char": "遍", "pinyin": ""},
                      {"char": "）", "pinyin": ""},
                      {"type": "linebreak"}
                    ]
                    """)
                    if let url = ChantFormatHelp.sampleURL {
                        NavigationLink {
                            ChantSampleView(url: url)
                        } label: {
                            Label("查看完整示例：\(url.lastPathComponent)", systemImage: "doc.text.magnifyingglass")
                        }
                        .accessibilityIdentifier("chantSampleLink")
                    }
                } header: {
                    Text("示例")
                } footer: {
                    Text("不是 JSON 数组、含无法识别的项（包括未知的 style）或没有任何字的文件不能导入。")
                }
            }
            .navigationTitle("诵经文本格式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// The bundled sample, still in the app bundle even if it was deleted from the shelf.
    static var sampleURL: URL? {
        Bundle.main.resourceURL?.appending(path: "\(ChantLibrary.bundledFolder)/佛教念诵集.json")
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
    }

    private func style(_ name: String, _ meaning: String) -> some View {
        LabeledContent {
            Text(meaning).multilineTextAlignment(.trailing)
        } label: {
            Text(name).font(.system(.body, design: .monospaced))
        }
    }
}

/// The sample file, one item per line so its ~10,000 items stay readable. Read-only, selectable,
/// with the system find bar; the original file can be shared or saved as a template.
struct ChantSampleView: View {
    let url: URL
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                ReadOnlyTextView(text: text)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
        .task {
            let url = url
            text = await Task.detached { ChantSampleView.compact(url) }.value
        }
    }

    /// Re-prints the item list with one item per line, keys in reading order.
    nonisolated static func compact(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        let order = ["type", "style", "char", "pinyin"]
        func quoted(_ s: String) -> String {
            let encoded = try? JSONEncoder().encode(s)
            return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(s)\""
        }
        let lines = items.enumerated().map { index, item in
            let keys = item.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            let body = keys.map { "\(quoted($0)): \(quoted(item[$0] ?? ""))" }.joined(separator: ", ")
            return "  {\(body)}" + (index < items.count - 1 ? "," : "")
        }
        return "[\n" + lines.joined(separator: "\n") + "\n]\n"
    }
}

/// A UITextView: SwiftUI `Text` is too slow for a few hundred KB, and this gives find for free.
private struct ReadOnlyTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isFindInteractionEnabled = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "chantSampleText"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
