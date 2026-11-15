import SwiftUI
import UIKit

enum Theme: String, CaseIterable, Codable, Sendable {
    case system, light, sepia, dark, black

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .sepia: "护眼"
        case .dark: "深色"
        case .black: "纯黑"
        }
    }

    /// The concrete theme once "follow system" is resolved.
    func resolved(for scheme: ColorScheme) -> Theme {
        self == .system ? (scheme == .dark ? .dark : .light) : self
    }

    func background(for scheme: ColorScheme) -> UIColor {
        switch resolved(for: scheme) {
        case .light: UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
        case .sepia: UIColor(red: 0xF4 / 255, green: 0xEC / 255, blue: 0xD8 / 255, alpha: 1)
        case .dark: UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        case .black: .black
        case .system: .systemBackground
        }
    }

    func foreground(for scheme: ColorScheme) -> UIColor {
        switch resolved(for: scheme) {
        case .light: UIColor(white: 0.12, alpha: 1)
        case .sepia: UIColor(red: 0x5B / 255, green: 0x46 / 255, blue: 0x36 / 255, alpha: 1)
        case .dark: UIColor(red: 0xD0 / 255, green: 0xD0 / 255, blue: 0xD0 / 255, alpha: 1)
        case .black: UIColor(red: 0xBB / 255, green: 0xBB / 255, blue: 0xBB / 255, alpha: 1)
        case .system: .label
        }
    }

    func secondary(for scheme: ColorScheme) -> UIColor {
        foreground(for: scheme).withAlphaComponent(0.55)
    }

    var isDark: Bool { self == .dark || self == .black }

    /// Colour scheme the chrome should adopt on top of this theme.
    func chromeScheme(for scheme: ColorScheme) -> ColorScheme {
        resolved(for: scheme).isDark ? .dark : .light
    }
}
