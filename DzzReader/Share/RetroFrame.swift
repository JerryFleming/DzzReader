import SwiftUI

/// Colours of the retro card: walnut frame, gilt lip, aged paper, faded-cinnabar rules, brown-black ink.
enum RetroPalette {
    static let woodDark = Color(red: 0.24, green: 0.13, blue: 0.06)
    static let woodMid = Color(red: 0.47, green: 0.28, blue: 0.13)
    static let woodLight = Color(red: 0.62, green: 0.40, blue: 0.20)
    static let grain = Color(red: 0.18, green: 0.09, blue: 0.04)
    static let gilt = Color(red: 0.80, green: 0.64, blue: 0.32)
    static let rule = Color(red: 0.47, green: 0.17, blue: 0.10)
    static let ink = Color(red: 0.16, green: 0.10, blue: 0.06)
    static let sepia = Color(red: 0.80, green: 0.62, blue: 0.38)
    static let cinnabar = Color(red: 0.75, green: 0.16, blue: 0.10)
}

/// A mitred walnut picture frame with drawn grain, a rounded-molding shade and a gilt inner lip.
/// The grain is seeded, so the frame looks the same on every redraw and in the exported image.
struct WoodFrame: View {
    var thickness: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, t = thickness
            // Each side is drawn as a horizontal strip (x along the side, y from the outer edge
            // inward) and moved into place.
            let sides: [(CGAffineTransform, CGFloat, UInt64)] = [
                (.identity, w, 1),                                                    // top
                (CGAffineTransform(translationX: w, y: h).rotated(by: .pi), w, 2),     // bottom
                (CGAffineTransform(translationX: 0, y: h).rotated(by: -.pi / 2), h, 3), // left
                (CGAffineTransform(translationX: w, y: 0).rotated(by: .pi / 2), h, 4),  // right
            ]
            for (transform, length, seed) in sides {
                var side = ctx
                side.concatenate(transform)
                Self.drawSide(&side, length: length, thickness: t, seed: seed)
            }

            let outer = CGRect(origin: .zero, size: size)
            ctx.stroke(Path(outer.insetBy(dx: 0.5, dy: 0.5)), with: .color(RetroPalette.grain), lineWidth: 1)
            ctx.stroke(Path(outer.insetBy(dx: 2, dy: 2)), with: .color(.white.opacity(0.12)), lineWidth: 1)
            // Gilt lip where frame meets paper, with a dark line for the shadow it casts.
            ctx.stroke(Path(outer.insetBy(dx: t - 2, dy: t - 2)), with: .color(RetroPalette.gilt), lineWidth: 2.5)
            ctx.stroke(Path(outer.insetBy(dx: t - 3, dy: t - 3)), with: .color(.white.opacity(0.35)), lineWidth: 0.5)
            ctx.stroke(Path(outer.insetBy(dx: t - 0.5, dy: t - 0.5)), with: .color(RetroPalette.grain.opacity(0.8)), lineWidth: 1)
        }
    }

    private static func drawSide(_ ctx: inout GraphicsContext, length: CGFloat, thickness t: CGFloat, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        var mitre = Path()
        mitre.move(to: .zero)
        mitre.addLine(to: CGPoint(x: length, y: 0))
        mitre.addLine(to: CGPoint(x: length - t, y: t))
        mitre.addLine(to: CGPoint(x: t, y: t))
        mitre.closeSubpath()
        ctx.clip(to: mitre)

        // Rounded molding: dark at the outer edge, catching the light just inside, dark at the lip.
        ctx.fill(mitre, with: .linearGradient(
            Gradient(stops: [
                .init(color: RetroPalette.woodDark, location: 0),
                .init(color: RetroPalette.woodLight, location: 0.3),
                .init(color: RetroPalette.woodMid, location: 0.65),
                .init(color: RetroPalette.woodDark, location: 1),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: t)))

        // Grain: long wavy lines, mostly dark, a few pale streaks.
        let lines = Int(t * 2.2)
        for _ in 0..<lines {
            let y0 = rng.next(in: -1...(t + 1))
            let a1 = rng.next(in: 0.2...1.4), f1 = rng.next(in: 0.004...0.02), p1 = rng.next(in: 0...6.3)
            let a2 = rng.next(in: 0...0.5), f2 = rng.next(in: 0.03...0.08), p2 = rng.next(in: 0...6.3)
            var line = Path()
            var x: CGFloat = 0
            line.move(to: CGPoint(x: 0, y: y0 + a1 * sin(p1) + a2 * sin(p2)))
            while x < length {
                x += 4
                line.addLine(to: CGPoint(x: x, y: y0 + a1 * sin(x * f1 + p1) + a2 * sin(x * f2 + p2)))
            }
            let pale = rng.next(in: 0...1) < 0.18
            let colour = pale ? Color.white.opacity(rng.next(in: 0.05...0.14)) : RetroPalette.grain.opacity(rng.next(in: 0.12...0.4))
            ctx.stroke(line, with: .color(colour), lineWidth: rng.next(in: 0.3...1.3))
        }

        // A soft sheen along the highlight of the molding.
        ctx.fill(Path(CGRect(x: 0, y: t * 0.22, width: length, height: t * 0.12)), with: .color(.white.opacity(0.08)))

        // The mitre joints.
        var joints = Path()
        joints.move(to: .zero); joints.addLine(to: CGPoint(x: t, y: t))
        joints.move(to: CGPoint(x: length, y: 0)); joints.addLine(to: CGPoint(x: length - t, y: t))
        ctx.stroke(joints, with: .color(RetroPalette.grain.opacity(0.7)), lineWidth: 1)
    }
}

/// Aged paper: the paper texture warmed to sepia, darkened toward the edges, with a classical
/// double rule (thick outside, thin inside) and a key-fret (回纹) ornament in each corner.
struct RetroPaper: View {
    /// Distance from the paper edge to the outer rule.
    static let ruleInset: CGFloat = 8
    /// How far the corner ornaments reach in from the inner rule; text keeps clear of it.
    static let clearance: CGFloat = 30

    var body: some View {
        ZStack {
            Image("QuotePaper").resizable(resizingMode: .tile)
            RetroPalette.sepia.opacity(0.35).blendMode(.multiply)
            // Foxed, darker edges.
            Rectangle()
                .strokeBorder(Color(red: 0.45, green: 0.30, blue: 0.15).opacity(0.45), lineWidth: 22)
                .blur(radius: 16)
            Canvas { ctx, size in Self.drawRules(&ctx, size: size) }
        }
        .clipped()
    }

    private static func drawRules(_ ctx: inout GraphicsContext, size: CGSize) {
        let colour = GraphicsContext.Shading.color(RetroPalette.rule.opacity(0.85))
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: ruleInset, dy: ruleInset)
        let inner = outer.insetBy(dx: 5, dy: 5)
        ctx.stroke(Path(outer), with: colour, lineWidth: 2.2)
        ctx.stroke(Path(inner), with: colour, lineWidth: 0.8)

        // A square spiral tucked into each corner of the inner rule, mirrored per corner.
        let u: CGFloat = 3.2
        var fret = Path()
        let points: [(CGFloat, CGFloat)] = [(0, 5), (0, 0), (5, 0), (5, 4), (1.5, 4), (1.5, 1.5), (3.5, 1.5), (3.5, 2.6), (2.6, 2.6)]
        fret.move(to: CGPoint(x: points[0].0 * u, y: points[0].1 * u))
        for p in points.dropFirst() { fret.addLine(to: CGPoint(x: p.0 * u, y: p.1 * u)) }
        let gap: CGFloat = 3
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: inner.minX + gap, y: inner.minY + gap), 1, 1),
            (CGPoint(x: inner.maxX - gap, y: inner.minY + gap), -1, 1),
            (CGPoint(x: inner.minX + gap, y: inner.maxY - gap), 1, -1),
            (CGPoint(x: inner.maxX - gap, y: inner.maxY - gap), -1, -1),
        ]
        for (origin, sx, sy) in corners {
            let placed = fret.applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: sx, y: sy))
            ctx.stroke(placed, with: colour, style: StrokeStyle(lineWidth: 1.2, lineCap: .square, lineJoin: .miter))
        }
    }
}

/// SplitMix64: a tiny deterministic generator so the drawn grain never changes between redraws.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(nextUInt64() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
