import CreatorGeometry
import Foundation

/// A written SVG and the typed texts its lettering had to replace with "?" (DR-5 R14).
public struct SVGOutput: Sendable {
    public var data: Data
    public var replacedTexts: [String]

    public init(data: Data, replacedTexts: [String]) {
        self.data = data
        self.replacedTexts = replacedTexts
    }
}

/// Writes one sheet picture as an SVG in millimetres (DR-5 R14). The bytes depend on nothing but the picture and the title:
/// numbers go through `PDFNumber`, layers in `DrawingLayer.allCases` order, no clock, no locale.
public enum SVGWriter {
    public static func write(_ picture: SheetPicture, title: String) -> SVGOutput {
        let page = picture.finite
        let style = DrawingStyle.of(page.standard)
        let (width, height) = (n(page.size.x), n(page.size.y))
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" "
        out += "width=\"\(width)mm\" height=\"\(height)mm\" viewBox=\"0 0 \(width) \(height)\">\n"
        out += "<title>\(escaped(title))</title>\n"
        out += "<g transform=\"matrix(1 0 0 -1 0 \(height))\">\n"
        for image in page.images { out += imageElement(image) }
        for layer in DrawingLayer.allCases {
            let strokes = page.strokes.filter { $0.layer == layer && !$0.segments.isEmpty }
            let fills = page.fills.filter { $0.layer == layer && $0.points.count >= 3 }
            let texts = page.texts.filter { $0.layer == layer && !$0.isNotice && !$0.run.bytes.isEmpty }
            if strokes.isEmpty && fills.isEmpty && texts.isEmpty { continue }
            out += "<g id=\"\(layer.rawValue)\">\n"
            for stroke in strokes { out += strokeElement(stroke, style: style) }
            for fill in fills { out += fillElement(fill) }
            for text in texts { out += textElement(text) }
            out += "</g>\n"
        }
        out += "</g>\n</svg>\n"
        return SVGOutput(data: Data(out.utf8), replacedTexts: ReplacedTexts.collect(page.texts.filter { !$0.isNotice }))
    }

    private static func n(_ value: Double) -> String { PDFNumber.format(value, decimals: 4) }

    // MARK: Elements

    /// The group flips y, so the picture un-flips itself about its rect's middle: row 0 lands on the rect's top edge (R14).
    private static func imageElement(_ image: SheetImage) -> String {
        let rect = image.rect
        let png = GreyPNG.encode(image.pixels).base64EncodedString()
        let uri = "data:image/png;base64," + png
        return "<image x=\"\(n(rect.min.x))\" y=\"\(n(rect.min.y))\" width=\"\(n(rect.width))\" height=\"\(n(rect.height))\" "
            + "preserveAspectRatio=\"none\" transform=\"matrix(1 0 0 -1 0 \(n(rect.min.y + rect.max.y)))\" "
            + "href=\"\(uri)\" xlink:href=\"\(uri)\"/>\n"
    }

    private static func strokeElement(_ stroke: SheetStroke, style: DrawingStyle) -> String {
        var element = "<path d=\"\(path(of: stroke.segments))\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(n(stroke.width))\""
        switch stroke.pattern {
        case .solid: break
        case .hidden: element += " stroke-dasharray=\"\(n(style.hiddenDash)) \(n(style.hiddenGap))\""
        case .centre: element += " stroke-dasharray=\"\(style.centreDash.map(n).joined(separator: " "))\""
        }
        return element + " stroke-linecap=\"butt\" stroke-linejoin=\"round\"/>\n"
    }

    private static func fillElement(_ fill: SheetFill) -> String {
        var d = ""
        for (index, point) in fill.points.enumerated() { d += "\(index == 0 ? "M" : "L")\(n(point.x)) \(n(point.y)) " }
        return "<path d=\"\(d)Z\" fill=\"#000\" stroke=\"none\"/>\n"
    }

    /// The text's own frame: x along its baseline, y down the page (SVG's), so the flipped group draws it upright.
    private static func textElement(_ text: SheetText) -> String {
        let em = text.height / Double(HelveticaMetrics.capHeight) * 1000
        let (c, s) = (cos(text.angle), sin(text.angle))
        var content = ""
        for byte in text.run.bytes { content += escaped(String(HelveticaMetrics.unicode(forWinAnsi: byte) ?? "?")) }
        return "<text transform=\"matrix(\(n(c)) \(n(s)) \(n(s)) \(n(-c)) \(n(text.origin.x)) \(n(text.origin.y)))\" "
            + "font-family=\"Helvetica, Arial, sans-serif\" font-size=\"\(n(em))\" textLength=\"\(n(text.run.width))\" "
            + "lengthAdjust=\"spacingAndGlyphs\" xml:space=\"preserve\" fill=\"#000\">\(content)</text>\n"
    }

    /// The same moves, lines and cubics the PDF's content stream writes.
    private static func path(of segments: [SheetSegment]) -> String {
        var out = ""
        var current: Vector2?
        func connect(to start: Vector2) {
            if let current, abs(current.x - start.x) < 1e-9, abs(current.y - start.y) < 1e-9 { return }
            out += "M\(n(start.x)) \(n(start.y)) "
        }
        for segment in segments {
            switch segment {
            case let .line(a, b):
                connect(to: a)
                out += "L\(n(b.x)) \(n(b.y)) "
                current = b
            case let .polyline(points):
                guard let first = points.first else { continue }
                connect(to: first)
                for point in points.dropFirst() { out += "L\(n(point.x)) \(n(point.y)) " }
                current = points.last
            case .arc, .ellipse:
                let pieces = segment.cubics()
                guard let first = pieces.first else { continue }
                connect(to: first.start)
                for piece in pieces {
                    out += "C\(n(piece.control1.x)) \(n(piece.control1.y)) \(n(piece.control2.x)) \(n(piece.control2.y)) "
                    out += "\(n(piece.end.x)) \(n(piece.end.y)) "
                }
                current = pieces.last?.end
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// XML text: the five markup characters escaped, and the control characters XML 1.0 forbids (U+0000 to U+001F except tab, line
    /// feed and carriage return) left out, so a typed title or note never makes the file unreadable.
    static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
