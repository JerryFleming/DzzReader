import CoreText
import Foundation

// Prints the outline of one BMP character (a single UTF-16 code unit; no surrogate pairs) as an SVG path, fitted into a square box.
// usage: glyph <font PostScript name> <one BMP character> <box size> <glyph height in box>
let usage = "usage: glyph <font PostScript name> <one BMP character> <box size> <glyph height in box>"
let args = CommandLine.arguments
guard args.count == 5 else {
    fputs(usage + "\n", stderr)
    exit(2)
}
guard let box = Double(args[3]), let height = Double(args[4]) else {
    fputs(usage + "\n", stderr)
    exit(2)
}
let font = CTFontCreateWithName(args[1] as CFString, 1000, nil)
guard (CTFontCopyPostScriptName(font) as String) == args[1] else { fatalError("font \(args[1]) not installed") }
let char = Array(args[2].utf16)
var glyph = CGGlyph()
guard CTFontGetGlyphsForCharacters(font, char, &glyph, 1), let path = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fatalError("no glyph")
}
let bounds = path.boundingBoxOfPath
let scale = height / Double(max(bounds.width, bounds.height))
let dx = (box - Double(bounds.width) * scale) / 2
let dy = (box - Double(bounds.height) * scale) / 2
func p(_ pt: CGPoint) -> String {
    let x = (Double(pt.x - bounds.minX)) * scale + dx
    let y = box - ((Double(pt.y - bounds.minY)) * scale + dy)   // flip: SVG y grows down
    return String(format: "%.1f %.1f", x, y)
}
var d = ""
path.applyWithBlock { element in
    let e = element.pointee
    switch e.type {
    case .moveToPoint: d += "M\(p(e.points[0]))"
    case .addLineToPoint: d += "L\(p(e.points[0]))"
    case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
    case .addCurveToPoint: d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
print(d)
