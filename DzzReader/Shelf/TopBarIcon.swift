import SwiftUI

/// The shelves' top-bar buttons: a rose glyph on a pale-rose disc (deep rose in dark), in the app icon's
/// palette (Scripts/make-app-icon.py). Used for 导入 and 下载 on 书架, 导入 and 格式说明 on 诵经,
/// and for the controls on 分享. 44pt, Apple's minimum tap target. Dims when disabled.
/// Pure SwiftUI, so it can be previewed off-device.
struct TopBarIcon: View {
    enum Glyph {
        case importFile, download, help
        /// A short text glyph (one symbol, or two characters such as "A+").
        case text(String)
    }

    let glyph: Glyph
    /// The badge's diameter; everything inside was drawn for 30pt and is scaled by `k`.
    static let size: CGFloat = 44
    private let k = TopBarIcon.size / 30
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    static let roseDeep = Color(red: 0xB8 / 255, green: 0x45 / 255, blue: 0x5E / 255)
    static let roseMid = Color(red: 0xDE / 255, green: 0x85 / 255, blue: 0x97 / 255)
    static let rosePale = Color(red: 0xF7 / 255, green: 0xD6 / 255, blue: 0xDC / 255)

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? Self.rosePale : Self.roseDeep }

    var body: some View {
        ZStack {
            Circle().fill(dark ? Self.roseDeep.opacity(0.35) : Self.rosePale)
            Circle().strokeBorder(dark ? Self.roseMid : Self.roseDeep.opacity(0.5), lineWidth: 1.5)
            switch glyph {
            case .importFile:
                Text("⤓\u{FE0E}")
                    .font(.system(size: 16 * k, weight: .semibold))
                    .foregroundStyle(ink)
            case .download:
                ZStack {
                    BadgeCloud()
                        .stroke(ink, style: StrokeStyle(lineWidth: 1.6 * k, lineJoin: .round))
                        .frame(width: 17 * k, height: 10 * k)
                        .offset(y: -3.5 * k)
                    Text("↓")
                        .font(.system(size: 10 * k, weight: .heavy))
                        .foregroundStyle(ink)
                        .offset(y: 5 * k)
                }
            case .help:
                Text("?")
                    .font(.system(size: 16 * k, weight: .semibold))
                    .foregroundStyle(ink)
            case .text(let s):
                Text(s.count > 1 ? s : s + "\u{FE0E}")
                    .font(.system(size: (s.count > 1 ? 13 : 16) * k, weight: .semibold))
                    .foregroundStyle(ink)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Circle())
    }
}

/// A small cloud outline: a small and a large lobe over a flat base. (The ☁ character renders as a filled blob.)
private struct BadgeCloud: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        let base = r.maxY
        let small = h * 0.36, big = h * 0.5
        let smallCentre = CGPoint(x: r.minX + small, y: base - small)
        let bigCentre = CGPoint(x: r.maxX - big - w * 0.04, y: r.minY + big)
        p.move(to: CGPoint(x: r.minX + small, y: base))
        p.addArc(center: smallCentre, radius: small, startAngle: .degrees(90), endAngle: .degrees(285), clockwise: false)
        p.addArc(center: bigCentre, radius: big, startAngle: .degrees(195), endAngle: .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}
