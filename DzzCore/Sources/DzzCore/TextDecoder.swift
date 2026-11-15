import Foundation

public struct DecodedText: Equatable, Sendable {
    public let text: String
    public let encodingName: String   // "utf-8", "utf-16", "gb18030", "big5"

    public init(text: String, encodingName: String) {
        self.text = text
        self.encodingName = encodingName
    }
}

public enum TextDecoder {
    public static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    public static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5.rawValue)))

    /// UTF-8 (BOM stripped) → UTF-16 with BOM → Foundation detection suggesting GB18030 then Big5.
    /// Line endings are normalised to "\n". Returns nil when nothing plausible decodes.
    public static func decode(_ data: Data) -> DecodedText? {
        if let result = decodeUTF8(data) { return result }
        if let result = decodeUTF16(data) { return result }
        if let result = detect(data) { return result }
        return nil
    }

    private static func decodeUTF8(_ data: Data) -> DecodedText? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard let s = String(data: bytes, encoding: .utf8) else { return nil }
        return DecodedText(text: normaliseLineEndings(s), encodingName: "utf-8")
    }

    private static func decodeUTF16(_ data: Data) -> DecodedText? {
        guard data.count >= 2 else { return nil }
        let hasBOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard hasBOM, let s = String(data: data, encoding: .utf16) else { return nil }
        return DecodedText(text: normaliseLineEndings(s), encodingName: "utf-16")
    }

    private static func detect(_ data: Data) -> DecodedText? {
        var converted: NSString?
        let options: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: [gb18030.rawValue, big5.rawValue],
            .allowLossyKey: false,
        ]
        let raw = NSString.stringEncoding(for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: nil)
        guard raw != 0, let s = converted as String? else { return nil }
        let encoding = String.Encoding(rawValue: raw)
        let name: String
        switch encoding {
        case gb18030: name = "gb18030"
        case big5: name = "big5"
        default:
            // Something else matched (e.g. Latin-1 for garbage); accept only if it is plausibly CJK text.
            guard s.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return nil }
            name = String(describing: encoding)
        }
        return DecodedText(text: normaliseLineEndings(s), encodingName: name)
    }

    private static func normaliseLineEndings(_ s: String) -> String {
        guard s.contains("\r") else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
