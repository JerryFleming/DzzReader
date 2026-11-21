import Foundation
import Testing
@testable import DzzCore

@Suite struct TarGzExtractorTests {
    /// Builds `repo-master/…` with bsdtar (which writes pax/ustar long names) and returns the .tar.gz.
    private func makeArchive(files: [String: String]) throws -> (archive: URL, scratch: URL) {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "tgz-\(UUID().uuidString)")
        let src = scratch.appending(path: "src/repo-master")
        for (path, text) in files {
            let url = src.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let archive = scratch.appending(path: "repo.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.environment = ["COPYFILE_DISABLE": "1"]   // no ._ AppleDouble entries
        tar.arguments = ["-czf", archive.path, "-C", scratch.appending(path: "src").path, "repo-master"]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)
        return (archive, scratch)
    }

    @Test func extractsStrippedFilteredFilesWithLongNames() throws {
        let longName = "00/" + String(repeating: "般若波罗蜜多", count: 8) + ".txt"   // > 100 bytes
        #expect(longName.utf8.count > 100)
        let big = String(repeating: "如是我闻。", count: 50_000)              // spans many chunks
        let (archive, scratch) = try makeArchive(files: [
            "toc.txt": "目录",
            "00/0001长阿含经.txt": big,
            longName: "心经",
            "README.md": "skip me",
        ])
        defer { try? FileManager.default.removeItem(at: scratch) }

        let out = scratch.appending(path: "out")
        var fractions: [Double] = []
        let count = try TarGzExtractor.extract(archive: archive, to: out, stripComponents: 1,
                                               include: { $0 != "README.md" },
                                               progress: { fractions.append($0) })
        #expect(count == 3)
        #expect(try String(contentsOf: out.appending(path: "toc.txt"), encoding: .utf8) == "目录")
        #expect(try String(contentsOf: out.appending(path: "00/0001长阿含经.txt"), encoding: .utf8) == big)
        #expect(try String(contentsOf: out.appending(path: longName), encoding: .utf8) == "心经")
        #expect(!FileManager.default.fileExists(atPath: out.appending(path: "README.md").path))
        #expect(fractions.last == 1)
    }

    @Test func rejectsNonGzip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notgz-\(UUID().uuidString)")
        try Data("<html>rate limited</html>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: TarGzExtractor.Failure.notGzip) {
            try TarGzExtractor.extract(archive: url, to: url.deletingLastPathComponent())
        }
    }

    @Test func readsPaxPath() {
        let record = "29 path=a/very/long/name.txt\n"
        #expect(record.utf8.count == 29)
        let body = Data(("19 comment=abcdefg\n" + record).utf8)
        #expect(TarParser.paxValue("path", in: body) == "a/very/long/name.txt")
    }

    /// Unpacks the real GitHub archive. Skipped unless DZZ_TARBALL points at a downloaded dzz .tar.gz.
    @Test func extractsRealArchive() throws {
        guard let path = ProcessInfo.processInfo.environment["DZZ_TARBALL"] else { return }
        let out = FileManager.default.temporaryDirectory.appending(path: "dzz-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let started = Date()
        let count = try TarGzExtractor.extract(archive: URL(fileURLWithPath: path), to: out, stripComponents: 1)
        print("Extracted \(count) files in \(Date().timeIntervalSince(started))s")
        #expect(count > 2900)
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "toc.txt").path))
    }
}
