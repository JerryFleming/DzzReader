import Compression
import Foundation

/// Unpacks a `.tar.gz` file (such as a GitHub source archive) to a folder, streaming, without
/// holding the archive in memory. Handles ustar names with a prefix, pax `path` records and GNU
/// long names; links and other special entries are skipped.
public enum TarGzExtractor {
    public enum Failure: Error, Equatable, LocalizedError {
        case notGzip
        case corruptArchive(String)

        public var errorDescription: String? {
            switch self {
            case .notGzip: "下载的文件不是 gzip 压缩包。"
            case .corruptArchive(let detail): "压缩包已损坏：\(detail)"
            }
        }
    }

    /// Extracts regular files and returns how many were written.
    /// - Parameters:
    ///   - stripComponents: leading path components to drop (GitHub archives wrap everything in `repo-branch/`).
    ///   - include: called with the stripped relative path; return false to skip the file.
    ///   - progress: fraction of the compressed archive consumed, 0...1.
    @discardableResult
    public static func extract(archive: URL, to destination: URL, stripComponents: Int = 0,
                               include: @escaping (String) -> Bool = { _ in true },
                               progress: (Double) -> Void = { _ in }) throws -> Int {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let total = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        let headerLength = try gzipHeaderLength(handle.read(upToCount: 64 * 1024) ?? Data())
        // The deflate stream sits between the gzip header and the 8-byte CRC/size trailer.
        guard total >= UInt64(headerLength) + 8 else { throw Failure.notGzip }
        let deflateEnd = total - 8
        try handle.seek(toOffset: UInt64(headerLength))

        let parser = TarParser(destination: destination, stripComponents: stripComponents, include: include)
        var parseError: Error?
        let filter = try OutputFilter(.decompress, using: .zlib) { chunk in
            guard let chunk, parseError == nil else { return }
            do { try parser.feed(chunk) } catch { parseError = error }
        }

        var offset = UInt64(headerLength)
        let chunkSize = 1 << 20
        while offset < deflateEnd {
            let count = Int(min(UInt64(chunkSize), deflateEnd - offset))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
            try filter.write(data)
            if let parseError { throw parseError }
            offset += UInt64(data.count)
            progress(Double(offset) / Double(deflateEnd))
        }
        try filter.finalize()
        if let parseError { throw parseError }
        return parser.filesWritten
    }

    /// Length of the gzip member header (RFC 1952) at the start of `data`.
    static func gzipHeaderLength(_ data: Data) throws -> Int {
        let b = [UInt8](data.prefix(10))
        guard b.count == 10, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { throw Failure.notGzip }
        let flags = b[3]
        var i = 10
        let bytes = [UInt8](data)
        func need(_ n: Int) throws { if i + n > bytes.count { throw Failure.notGzip } }
        if flags & 0x04 != 0 {                       // FEXTRA
            try need(2)
            i += 2 + Int(bytes[i]) + Int(bytes[i + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {   // FNAME, FCOMMENT: zero-terminated
            while true {
                try need(1)
                i += 1
                if bytes[i - 1] == 0 { break }
            }
        }
        if flags & 0x02 != 0 { i += 2 }              // FHCRC
        try need(0)
        return i
    }
}

/// A tar stream fed in arbitrary chunks.
final class TarParser {
    private let destination: URL
    private let stripComponents: Int
    private let include: (String) -> Bool
    private var buffer = Data()
    private var finished = false
    private var nextPath: String?                    // from a pax `x` or GNU `L` record
    private var createdDirectories = Set<String>()
    private(set) var filesWritten = 0

    init(destination: URL, stripComponents: Int, include: @escaping (String) -> Bool) {
        self.destination = destination
        self.stripComponents = stripComponents
        self.include = include
    }

    func feed(_ chunk: Data) throws {
        buffer.append(chunk)
        while !finished, buffer.count >= 512 {
            let header = [UInt8](buffer.prefix(512))
            if header.allSatisfy({ $0 == 0 }) {      // end-of-archive marker
                finished = true
                buffer.removeAll()
                return
            }
            try verifyChecksum(header)
            let size = try octal(header, 124, 12)
            let padded = (size + 511) / 512 * 512
            guard buffer.count >= 512 + padded else { return }   // wait for the whole entry
            let start = buffer.startIndex + 512
            let body = buffer.subdata(in: start ..< start + size)
            buffer.removeSubrange(buffer.startIndex ..< start + padded)
            try handle(header: header, body: body)
        }
    }

    private func handle(header: [UInt8], body: Data) throws {
        let type = header[156]
        switch type {
        case UInt8(ascii: "x"):                      // pax extended header for the next entry
            if let path = Self.paxValue("path", in: body) { nextPath = path }
        case UInt8(ascii: "L"):                      // GNU long name for the next entry
            nextPath = String(decoding: body.prefix { $0 != 0 }, as: UTF8.self)
        case UInt8(ascii: "g"):                      // pax global header (GitHub puts the commit id here)
            break
        case 0, UInt8(ascii: "0"), UInt8(ascii: "7"):  // regular file
            let path = nextPath ?? ustarName(header)
            nextPath = nil
            try write(body, to: path)
        default:                                     // directories, links, devices: skipped
            nextPath = nil
        }
    }

    private func write(_ body: Data, to rawPath: String) throws {
        let components = rawPath.split(separator: "/").map(String.init)
        guard components.count > stripComponents else { return }
        let parts = Array(components.dropFirst(stripComponents))
        guard !parts.contains(where: { $0 == ".." || $0 == "." }) else {
            throw TarGzExtractor.Failure.corruptArchive("非法路径 \(rawPath)")
        }
        let relative = parts.joined(separator: "/")
        guard include(relative) else { return }
        let directory = parts.dropLast().joined(separator: "/")
        if !createdDirectories.contains(directory) {
            try FileManager.default.createDirectory(at: destination.appending(path: directory),
                                                    withIntermediateDirectories: true)
            createdDirectories.insert(directory)
        }
        try body.write(to: destination.appending(path: relative))
        filesWritten += 1
    }

    private func ustarName(_ header: [UInt8]) -> String {
        let name = Self.cString(header, 0, 100)
        let isUstar = Self.cString(header, 257, 6).hasPrefix("ustar")
        let prefix = isUstar ? Self.cString(header, 345, 155) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    private func verifyChecksum(_ header: [UInt8]) throws {
        let stored = try octal(header, 148, 8)
        var sum = 0
        for (i, byte) in header.enumerated() { sum += (148 ..< 156).contains(i) ? 32 : Int(byte) }
        guard sum == stored else { throw TarGzExtractor.Failure.corruptArchive("校验和不符") }
    }

    private func octal(_ header: [UInt8], _ offset: Int, _ length: Int) throws -> Int {
        let text = Self.cString(header, offset, length).trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        guard let value = Int(text, radix: 8) else {
            throw TarGzExtractor.Failure.corruptArchive("无法读取条目头")
        }
        return value
    }

    private static func cString(_ header: [UInt8], _ offset: Int, _ length: Int) -> String {
        let field = header[offset ..< offset + length]
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Records are `"<len> <key>=<value>\n"`.
    static func paxValue(_ key: String, in body: Data) -> String? {
        var bytes = Substring(String(decoding: body, as: UTF8.self))
        while let space = bytes.firstIndex(of: " "), let length = Int(bytes[..<space]), length > 0 {
            let utf8 = bytes.utf8
            guard let end = utf8.index(utf8.startIndex, offsetBy: length, limitedBy: utf8.endIndex) else { break }
            let record = bytes[bytes.index(after: space) ..< end].dropLast()   // drop "\n"
            if let eq = record.firstIndex(of: "="), record[..<eq] == key {
                return String(record[record.index(after: eq)...])
            }
            bytes = bytes[end...]
        }
        return nil
    }
}
