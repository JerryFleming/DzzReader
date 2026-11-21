import Foundation
import Observation
import SwiftData
import UIKit
import DzzCore

/// Where downloaded books live on the device. Nothing is shipped in the app: the 书架's download
/// button fetches a `.tar.gz` (by default the dzz corpus on GitHub) and unpacks its `.txt` files into
/// Application Support/Books, replacing whatever was downloaded before. The folder is excluded from
/// iCloud backup, since it can be fetched again.
enum Corpus {
    static let defaultArchiveURL = "https://github.com/JerryFleming/dzz/archive/refs/heads/master.tar.gz"

    /// Base that downloaded books' `relativePath` ("Books/00/0001长阿含经.txt") resolves against.
    static var root: URL { URL.applicationSupportDirectory }
    static var booksDirectory: URL { root.appending(path: "Books") }
    static var hasBooks: Bool {
        FileManager.default.fileExists(atPath: booksDirectory.path)
    }

    /// Only text files are kept; hidden entries (.git, ._ AppleDouble files) are dropped.
    static func keeps(_ relativePath: String) -> Bool {
        relativePath.lowercased().hasSuffix(".txt")
            && !relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    static var staging: URL { root.appending(path: "Books.partial") }

    /// Unpacks a downloaded archive into the staging folder and returns the folder holding its books
    /// (an archive that wraps everything in one folder, as GitHub's do, is unwrapped).
    nonisolated static func unpack(archive: URL, progress: (Double) -> Void) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let count = try TarGzExtractor.extract(archive: archive, to: staging, include: keeps, progress: progress)
            guard count > 0 else { throw CorpusError.noBooks }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        var top = staging
        while true {
            let items = try fm.contentsOfDirectory(at: top, includingPropertiesForKeys: [.isDirectoryKey])
            guard items.count == 1, let only = items.first,
                  (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !fm.fileExists(atPath: top.appending(path: "toc.txt").path) else { break }
            top = only
        }
        return top
    }

    /// Moves the unpacked books into Books/: same-path files are overwritten, everything else already
    /// there is kept. Removes the staging folder.
    nonisolated static func merge(from top: URL) throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: staging) }
        // Merge into Books/: same-path files are overwritten, everything else already there is kept.
        try fm.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        let walker = fm.enumerator(at: top, includingPropertiesForKeys: [.isRegularFileKey])
        let topPath = top.standardizedFileURL.path + "/"
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(topPath.count))
            let dest = booksDirectory.appending(path: relative)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: url, to: dest)
        }
        var dest = booksDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dest.setResourceValues(values)
    }
}

enum CorpusError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case noBooks

    var errorDescription: String? {
        switch self {
        case .invalidURL: "网址无效。"
        case .badResponse(let code): "服务器返回错误（HTTP \(code)）。"
        case .noBooks: "压缩包里没有 txt 文件。"
        }
    }
}

/// Drives a download and unpacking, reporting progress for the UI.
@Observable @MainActor
final class CorpusDownloader {
    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, expected: Int64?)
        case extracting(Double)
        case failed(String)
        case done
    }

    private(set) var phase = Phase.idle

    /// Downloads the `.tar.gz` at `urlString`, adds its books to the shelf and their files to Books/.
    /// Books already there stay; files with the same path are overwritten.
    func run(urlString: String, context: ModelContext) async {
        switch phase {
        case .downloading, .extracting: return
        case .idle, .failed, .done: break
        }
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http", "file"].contains(scheme) else {
            phase = .failed(CorpusError.invalidURL.localizedDescription)
            return
        }
        phase = .downloading(received: 0, expected: nil)
        UIApplication.shared.isIdleTimerDisabled = true   // don't let auto-lock cut the download off
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        do {
            let archive = try await download(url)
            defer { try? FileManager.default.removeItem(at: archive) }
            phase = .extracting(0)
            let top = try await Task.detached(priority: .userInitiated) { [weak self] in
                var last = 0.0
                return try Corpus.unpack(archive: archive) { fraction in
                    guard fraction - last >= 0.01 || fraction == 1 else { return }
                    last = fraction
                    Task { @MainActor in
                        guard let self, case .extracting = self.phase else { return }   // may land after .done
                        self.phase = .extracting(fraction)
                    }
                }
            }.value
            // Catalogue from the unpacked archive alone, so its own toc.txt (or lack of one) decides
            // how its books are grouped, whatever was downloaded before.
            do {
                _ = try CatalogLoader.load(booksDirectory: top, context: context)
            } catch {
                try? FileManager.default.removeItem(at: Corpus.staging)
                throw error
            }
            try await Task.detached(priority: .userInitiated) { try Corpus.merge(from: top) }.value
            CatalogLoader.resetSections()
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Downloads to a temporary file and returns its URL (which the caller deletes).
    private func download(_ url: URL) async throws -> URL {
        let tracker = TaskTracker()
        let task = Task.detached { () -> (URL, URLResponse) in
            try await URLSession.shared.download(from: url, delegate: tracker)
        }
        // GitHub builds the tarball on the fly, so there is usually no Content-Length; show the
        // bytes received rather than relying on a fraction.
        let poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, case .downloading = self.phase, let t = tracker.task else { continue }
                let expected = t.countOfBytesExpectedToReceive
                self.phase = .downloading(received: t.countOfBytesReceived, expected: expected > 0 ? expected : nil)
            }
        }
        defer { poller.cancel() }
        let (temp, response) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: temp)
            throw CorpusError.badResponse(http.statusCode)
        }
        let kept = FileManager.default.temporaryDirectory.appending(path: "dzz-\(UUID().uuidString).tar.gz")
        try FileManager.default.moveItem(at: temp, to: kept)
        return kept
    }
}

/// Remembers the download task URLSession creates, so its byte counters can be read.
private final class TaskTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionTask?
    var task: URLSessionTask? { lock.withLock { _task } }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _task = task }
    }
}
