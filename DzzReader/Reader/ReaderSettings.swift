import Foundation
import Observation

/// Reader appearance, persisted in UserDefaults.
@Observable @MainActor
final class ReaderSettings {
    struct Snapshot: Equatable {
        let theme: Theme
        let fontName: String
        let fontSize: Double
        let lineSpacing: Double
        let margin: Double
    }

    static let curatedFonts: [(name: String, family: String)] = [
        ("系统", ""),
        ("宋体", "Songti SC"),
        ("楷体", "Kaiti SC"),
        ("黑体", "Heiti SC"),
        ("圆体", "Yuanti SC"),
    ]

    static let fontSizeRange: ClosedRange<Double> = 14...40
    static let lineSpacingRange: ClosedRange<Double> = 1.2...2.2
    static let marginRange: ClosedRange<Double> = 8...40
    /// Auto-scroll speed in points per second.
    static let autoScrollSpeedRange: ClosedRange<Double> = 5...150

    @ObservationIgnored private let defaults: UserDefaults

    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "reader.theme") } }
    var fontName: String { didSet { defaults.set(fontName, forKey: "reader.fontName") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "reader.fontSize") } }
    var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: "reader.lineSpacing") } }
    var margin: Double { didSet { defaults.set(margin, forKey: "reader.margin") } }
    // Not part of `snapshot`: changing this must not rebuild the chapter text.
    var autoScrollSpeed: Double { didSet { defaults.set(autoScrollSpeed, forKey: "reader.autoScrollSpeed") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .system
        fontName = defaults.string(forKey: "reader.fontName") ?? ""
        fontSize = defaults.object(forKey: "reader.fontSize") as? Double ?? 20
        lineSpacing = defaults.object(forKey: "reader.lineSpacing") as? Double ?? 1.6
        margin = defaults.object(forKey: "reader.margin") as? Double ?? 20
        autoScrollSpeed = defaults.object(forKey: "reader.autoScrollSpeed") as? Double ?? 30
    }

    var snapshot: Snapshot {
        Snapshot(theme: theme, fontName: fontName, fontSize: fontSize, lineSpacing: lineSpacing, margin: margin)
    }
}
