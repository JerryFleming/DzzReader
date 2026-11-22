import SwiftData
import SwiftUI

/// Downloads a `.tar.gz` of books (the dzz corpus by default) and replaces the downloaded books with it.
struct DownloadBooksSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("corpus.url") private var urlString = Corpus.defaultArchiveURL
    @State private var downloader = CorpusDownloader()

    private var busy: Bool {
        switch downloader.phase {
        case .downloading, .extracting: true
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DoneBarURLField(placeholder: "tar.gz 网址", text: $urlString)
                        .disabled(busy)
                        .accessibilityIdentifier("downloadURL")
                    if urlString != Corpus.defaultArchiveURL {
                        Button("恢复默认网址") { urlString = Corpus.defaultArchiveURL }
                            .disabled(busy)
                    }
                } header: {
                    Text("下载地址")
                } footer: {
                    Text("默认下载《大正藏》（约 130 MB，解压后约 350 MB）。压缩包中的 txt 文件会加入书架，同名文件被覆盖，已有的书不会删除；若含 toc.txt，按其中的部分组，否则列在未命名的分组里。导入的书不受影响。")
                }

                Section {
                    status
                }
            }
            .navigationTitle("下载经文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .onChange(of: downloader.phase) { _, phase in
                guard phase == .done else { return }
                dismiss()
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch downloader.phase {
        case .idle, .failed, .done:
            if case let .failed(message) = downloader.phase {
                Text("下载失败：\(message)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await downloader.run(urlString: urlString, context: context) }
            } label: {
                Text("下载")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("startDownload")
        case let .downloading(received, expected):
            VStack(alignment: .leading, spacing: 8) {
                if let expected {
                    ProgressView(value: Double(received), total: Double(expected))
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Text("正在下载… \(megabytes(received))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case let .extracting(fraction):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction)
                Text("正在解压… \(Int(fraction * 100))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
