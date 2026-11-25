import CreatorGeometry
import CreatorKernel
import Foundation

/// A written DXF and the typed texts its lettering had to replace with "?" (plan R13).
public struct DXFOutput: Sendable {
    public var data: Data
    public var replacedTexts: [String]

    public init(data: Data, replacedTexts: [String]) {
        self.data = data
        self.replacedTexts = replacedTexts
    }
}

/// Writes strokes and texts as an ASCII DXF, release 2000, in millimetres (plan R24). The bytes depend on nothing but the
/// input: handles are sequential, numbers go through `PDFNumber`, nothing iterates a dictionary.
public enum DXFWriter {
    public static func write(
        strokes: [SheetStroke], texts: [SheetText], extent: Rect2D, style: DrawingStyle
    ) -> DXFOutput {
        var handles = DXFHandles()
        let set = DXFHandleSet(&handles)
        var entities = DXFText()
        entities.add(0, "SECTION")
        entities.add(2, "ENTITIES")
        for stroke in strokes {
            for segment in stroke.segments { entity(segment, of: stroke, owner: set.modelRecord, handles: &handles, into: &entities) }
        }
        for text in texts where !text.run.shown.isEmpty {
            textEntity(text, owner: set.modelRecord, handles: &handles, into: &entities)
        }
        entities.add(0, "ENDSEC")

        var file = DXFText()
        file.add(DXFTables.header(seed: handles.seed, extent: extent))
        file.add(DXFTables.classes)
        file.add(DXFTables.tables(set, style: style, extent: extent))
        file.add(DXFTables.blocks(set))
        file.add(entities)
        file.add(DXFObjects.objects(set, extent: extent))
        file.add(0, "EOF")
        return DXFOutput(data: Data(file.text.utf8), replacedTexts: ReplacedTexts.collect(texts))
    }

    /// The open sheet, in sheet millimetres.
    public static func sheet(_ picture: SheetPicture, style: DrawingStyle) -> DXFOutput {
        write(
            strokes: picture.strokes, texts: picture.texts, extent: Rect2D(min: .zero, max: picture.size), style: style)
    }

    /// One view at 1:1 in model millimetres, x and y as the view plane's (plan R24): no frame and no texts.
    public static func view(_ projection: Projection2D, view: DrawingView, style: DrawingStyle) -> DXFOutput {
        guard let bounds = projection.bounds else {
            return write(strokes: [], texts: [], extent: Rect2D(min: .zero, max: .zero), style: style)
        }
        let strokes = ViewLinework.strokes(for: projection, view: view, center: bounds.center, scale: 1, style: style)
        return write(strokes: strokes, texts: [], extent: bounds, style: style)
    }

    // MARK: Entities

    private static func begin(
        _ type: String, stroke: SheetStroke, owner: String, handles: inout DXFHandles, into t: inout DXFText
    ) {
        t.add(0, type)
        t.add(5, handles.make())
        t.add(330, owner)
        t.add(100, "AcDbEntity")
        t.add(8, stroke.layer.rawValue)
        if stroke.pattern == .hidden && stroke.layer != .hidden { t.add(6, "DASHED") }
        t.add(370, DXFTables.lineweight(stroke.width))
    }

    private static func entity(
        _ segment: SheetSegment, of stroke: SheetStroke, owner: String, handles: inout DXFHandles, into t: inout DXFText
    ) {
        let tau = 2 * Double.pi
        switch segment {
        case let .line(a, b):
            begin("LINE", stroke: stroke, owner: owner, handles: &handles, into: &t)
            t.add(100, "AcDbLine")
            t.add(10, a.x)
            t.add(20, a.y)
            t.add(30, 0.0)
            t.add(11, b.x)
            t.add(21, b.y)
            t.add(31, 0.0)
        case let .polyline(points):
            guard points.count >= 2 else { return }
            begin("LWPOLYLINE", stroke: stroke, owner: owner, handles: &handles, into: &t)
            t.add(100, "AcDbPolyline")
            t.add(90, points.count)
            t.add(70, 0)
            for point in points {
                t.add(10, point.x)
                t.add(20, point.y)
            }
        case let .arc(center, radius, start, sweep):
            if abs(sweep) >= tau - 1e-9 {
                begin("CIRCLE", stroke: stroke, owner: owner, handles: &handles, into: &t)
                t.add(100, "AcDbCircle")
                t.add(10, center.x)
                t.add(20, center.y)
                t.add(30, 0.0)
                t.add(40, radius)
            } else {
                let first = sweep >= 0 ? start : start + sweep
                begin("ARC", stroke: stroke, owner: owner, handles: &handles, into: &t)
                t.add(100, "AcDbCircle")
                t.add(10, center.x)
                t.add(20, center.y)
                t.add(30, 0.0)
                t.add(40, radius)
                t.add(100, "AcDbArc")
                t.add(50, degrees(first))
                t.add(51, degrees(first + abs(sweep)))
            }
        case let .ellipse(center, axis, major, minor, start, sweep):
            let geometry = EllipseGeometry(
                center: center, axis: axis, major: major, minor: minor, start: start, sweep: sweep)
            ellipse(geometry, stroke: stroke, owner: owner, handles: &handles, into: &t)
        }
    }

    private struct EllipseGeometry {
        var center: Vector2
        var axis: Vector2
        var major: Double
        var minor: Double
        var start: Double
        var sweep: Double
    }

    private static func ellipse(
        _ geometry: EllipseGeometry, stroke: SheetStroke, owner: String, handles: inout DXFHandles,
        into t: inout DXFText
    ) {
        let (center, axis, major, minor, start, sweep) =
            (geometry.center, geometry.axis, geometry.major, geometry.minor, geometry.start, geometry.sweep)
        let tau = 2 * Double.pi
        let length = axis.length
        var u = length > 0 ? Vector2(axis.x / length, axis.y / length) : Vector2(1, 0)
        var a = major, b = minor
        var first = sweep >= 0 ? start : start + sweep
        // DXF wants the longer axis as the major one.
        if b > a {
            u = Vector2(-u.y, u.x)
            swap(&a, &b)
            first -= Double.pi / 2
        }
        guard a > 0 else { return }
        var from = 0.0, to = tau
        if abs(sweep) < tau - 1e-9 {
            from = wrapped(first, tau)
            to = wrapped(first + abs(sweep), tau)
        }
        begin("ELLIPSE", stroke: stroke, owner: owner, handles: &handles, into: &t)
        t.add(100, "AcDbEllipse")
        t.add(10, center.x)
        t.add(20, center.y)
        t.add(30, 0.0)
        t.add(11, u.x * a)
        t.add(21, u.y * a)
        t.add(31, 0.0)
        t.add(210, 0.0)
        t.add(220, 0.0)
        t.add(230, 1.0)
        t.add(40, b / a, decimals: 9)
        t.add(41, from, decimals: 9)
        t.add(42, to, decimals: 9)
    }

    private static func wrapped(_ value: Double, _ period: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: period)
        if result < 0 { result += period }
        return result >= period ? 0 : result
    }

    /// An angle in degrees in [0, 360), rounded to the six decimals the file keeps.
    private static func degrees(_ radians: Double) -> Double {
        let rounded = (wrapped(radians * 180 / Double.pi, 360) * 1e6).rounded() / 1e6
        return rounded >= 360 ? 0 : rounded
    }

    private static func textEntity(_ text: SheetText, owner: String, handles: inout DXFHandles, into t: inout DXFText) {
        t.add(0, "TEXT")
        t.add(5, handles.make())
        t.add(330, owner)
        t.add(100, "AcDbEntity")
        t.add(8, text.layer.rawValue)
        t.add(100, "AcDbText")
        t.add(10, text.origin.x)
        t.add(20, text.origin.y)
        t.add(30, 0.0)
        t.add(40, text.height)
        t.add(1, escaped(text.run.shown))
        t.add(7, "Standard")
        t.add(100, "AcDbText")
    }

    /// DXF's text codes: `%%c` for Ø, `%%p` for ±, `%%d` for °, `%%%` for a percent sign, `\U+XXXX` for anything else
    /// outside ASCII, so the file is ASCII whatever the code page.
    static func escaped(_ shown: String) -> String {
        var out = ""
        for scalar in shown.unicodeScalars {
            switch scalar.value {
            case 0xD8: out += "%%c"
            case 0xB1: out += "%%p"
            case 0xB0: out += "%%d"
            case 0x25: out += "%%%"
            case 0x20...0x7E: out.unicodeScalars.append(scalar)
            default:
                let digits = String(scalar.value, radix: 16, uppercase: true)
                out += "\\U+" + String(repeating: "0", count: Swift.max(0, 4 - digits.count)) + digits
            }
        }
        return out
    }
}
