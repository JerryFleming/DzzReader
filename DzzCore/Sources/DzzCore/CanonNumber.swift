import Foundation

/// Taishō 经号 handling: four digits with an optional lowercase suffix ("0026", "0894a").
public enum CanonNumber {
    private static let pattern = try! NSRegularExpression(pattern: #"^(\d{4})([a-z]?)"#)

    /// "0894a苏悉地羯罗供养法.txt" → "0894a"; "toc.txt" → nil
    public static func parse(filename: String) -> String? {
        let ns = filename as NSString
        guard let m = pattern.firstMatch(in: filename, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: m.range)
    }

    public static func isValid(_ number: String) -> Bool {
        let ns = number as NSString
        guard let m = pattern.firstMatch(in: number, range: NSRange(location: 0, length: ns.length)) else {
            return false
        }
        return m.range.length == ns.length
    }

    /// "0894a" → 894
    public static func numericPart(_ number: String) -> Int {
        Int(number.prefix(4)) ?? 0
    }

    /// "0026" → 26000; "0894a" → 894001; "0894b" → 894002
    public static func sortKey(_ number: String) -> Int {
        let suffix = number.dropFirst(4)
        let letter = suffix.first.map { Int($0.asciiValue ?? 96) - 96 } ?? 0
        return numericPart(number) * 1000 + letter
    }
}
