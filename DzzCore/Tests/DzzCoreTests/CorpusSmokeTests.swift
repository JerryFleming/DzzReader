import Foundation
import Testing
@testable import DzzCore

/// Runs the indexer across the whole corpus. Skipped unless DZZ_CORPUS points at the dzz folder.
@Suite struct CorpusSmoke {
    @Test func indexesEveryFile() throws {
        guard let root = ProcessInfo.processInfo.environment["DZZ_CORPUS"] else { return }
        let rootURL = URL(fileURLWithPath: root)
        let toc = TocParser.parse(try String(contentsOf: rootURL.appendingPathComponent("toc.txt"), encoding: .utf8))
        let juanByNumber = Dictionary(toc.entries.map { ($0.number, $0.juanCount) }, uniquingKeysWith: { a, _ in a })

        let fm = FileManager.default
        var files: [URL] = []
        for dir in try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) where dir.lastPathComponent.range(of: #"^\d\d$"#, options: .regularExpression) != nil {
            files += try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "txt" }
        }
        files.sort { $0.path < $1.path }

        var mismatches: [(Int, String)] = []
        var totalChapters = 0, totalSections = 0, splitFiles = 0, exact = 0, withToc = 0
        let started = Date()
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let title = String(url.deletingPathExtension().lastPathComponent.dropFirst(4))
            let chapters = ChapterIndexer.index(text: text, bookTitle: title)
            if let debug = ProcessInfo.processInfo.environment["DZZ_DEBUG_FILE"], url.lastPathComponent.hasPrefix(debug) {
                for c in chapters { print("DEBUG \(c.startOffset)-\(c.endOffset) \(c.title) sections=\(c.sections.count)") }
            }
            #expect(!chapters.isEmpty)
            #expect(chapters.first?.startOffset == 0)
            #expect(chapters.last?.endOffset == (text as NSString).length)
            for (a, b) in zip(chapters, chapters.dropFirst()) { #expect(a.endOffset == b.startOffset, "\(url.lastPathComponent)") }
            for c in chapters {
                #expect(c.length <= ChapterIndexer.oversizeLimit, "\(url.lastPathComponent) \(c.title) \(c.length)")
                for s in c.sections { #expect(s.offset >= c.startOffset && s.offset < c.endOffset) }
                totalSections += c.sections.count
            }
            totalChapters += chapters.count
            if chapters.contains(where: { $0.title.hasSuffix("）") && $0.title.contains("/") }) { splitFiles += 1 }

            if let number = CanonNumber.parse(filename: url.lastPathComponent), let expected = juanByNumber[number] ?? nil {
                withToc += 1
                var distinct = Set<String>()
                for c in chapters where c.title != "卷首" {
                    distinct.insert(c.title.replacingOccurrences(of: #"（\d+/\d+）$"#, with: "", options: .regularExpression))
                }
                let got = distinct.count
                if got == expected { exact += 1 } else { mismatches.append((abs(got - expected), "\(url.lastPathComponent): got \(got) expected \(expected)")) }
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        print("CORPUS: files=\(files.count) chapters=\(totalChapters) sections=\(totalSections) splitFiles=\(splitFiles) exactJuanMatch=\(exact)/\(withToc) elapsed=\(String(format: "%.1f", elapsed))s")
        for (_, line) in mismatches.sorted(by: { $0.0 > $1.0 }).prefix(15) { print("MISMATCH \(line)") }
        let within1 = mismatches.filter { $0.0 <= 1 }.count
        print("CORPUS: mismatches=\(mismatches.count) ofWhichOffByOne=\(within1)")
    }
}
