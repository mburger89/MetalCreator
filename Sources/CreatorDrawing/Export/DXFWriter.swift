import CreatorGeometry
import CreatorKernel
import Foundation

/// A written DXF and the typed texts its lettering had to replace with "?" (plan R13).
public struct DXFOutput: Sendable {
    public var data: Data
    public var replacedTexts: [String]
    /// True when the sheet held a picture, which a DXF cannot: its rectangle is written instead (DR-5 R13).
    public var leftOutImages: Bool

    public init(data: Data, replacedTexts: [String], leftOutImages: Bool = false) {
        self.data = data
        self.replacedTexts = replacedTexts
        self.leftOutImages = leftOutImages
    }
}

/// Writes strokes and texts as an ASCII DXF, release 2000, in millimetres (plan R24). The bytes depend on nothing but the
/// input: handles are sequential, numbers go through `PDFNumber`, nothing iterates a dictionary.
public enum DXFWriter {
    public static func write(
        strokes: [SheetStroke], texts: [SheetText], fills: [SheetFill] = [], images: [SheetImage] = [], extent: Rect2D,
        style: DrawingStyle
    ) -> DXFOutput {
        var handles = DXFHandles()
        let set = DXFHandleSet(&handles)
        var entities = DXFText()
        entities.add(0, "SECTION")
        entities.add(2, "ENTITIES")
        for stroke in strokes {
            for segment in stroke.segments { entity(segment, of: stroke, owner: set.modelRecord, handles: &handles, into: &entities) }
        }
        for image in images {
            let (low, high) = (image.rect.min, image.rect.max)
            let outline = [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y), low]
            entity(
                .polyline(outline), of: SheetStroke(segments: [], width: style.thin, layer: .frame),
                owner: set.modelRecord, handles: &handles, into: &entities)
        }
        for fill in fills { solids(fill, owner: set.modelRecord, handles: &handles, into: &entities) }
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
        return DXFOutput(
            data: Data(file.text.utf8), replacedTexts: ReplacedTexts.collect(texts), leftOutImages: !images.isEmpty)
    }

    /// The open sheet, in sheet millimetres.
    public static func sheet(_ picture: SheetPicture, style: DrawingStyle) -> DXFOutput {
        write(
            strokes: picture.strokes, texts: picture.texts, fills: picture.fills, images: picture.images,
            extent: Rect2D(min: .zero, max: picture.size), style: style)
    }

    /// One view at 1:1 in model millimetres, x and y as the view plane's (plan R24): no frame and no texts. With `annotations` (plan
    /// R22) the view's own dimensions, callouts, notes and leaders from the sheet's picture come too, mapped back by `mapping`
    /// (sheet minus offset, over scale) with their text heights over the scale, so the geometry measures true and the lettering keeps
    /// its size against the part.
    public static func view(
        _ projection: Projection2D, view: DrawingView, style: DrawingStyle,
        annotations: (picture: SheetPicture, mapping: ViewMapping)? = nil
    ) -> DXFOutput {
        guard let bounds = projection.bounds else {
            return write(strokes: [], texts: [], extent: Rect2D(min: .zero, max: .zero), style: style)
        }
        var strokes = ViewLinework.strokes(for: projection, view: view, center: bounds.center, scale: 1, style: style)
        var (texts, fills): ([SheetText], [SheetFill]) = ([], [])
        var extent = bounds
        if let (picture, mapping) = annotations {
            let (back, shift) = (1 / mapping.scale, mapping.offset * (-1 / mapping.scale))
            // The view's automatic centre marks carry no annotation but sit alone on the centre layer among a view's own strokes; a
            // section's hatch, a detail's boundary and the marks of the views made from this one are the view's too (DR-3 R15).
            for stroke in picture.strokes where stroke.view == view.id
                && (stroke.annotation != nil || stroke.layer == .center || stroke.layer == .hatch || stroke.mark != nil) {
                var moved = stroke
                moved.segments = stroke.segments.map { $0.transformed(scale: back, offset: shift) }
                extent = extent.union(moved.bounds)
                strokes.append(moved)
            }
            for fill in picture.fills where fill.view == view.id && (fill.annotation != nil || fill.mark != nil) {
                var moved = fill
                moved.points = fill.points.map { mapping.model($0) }
                if let box = Rect2D(points: moved.points) { extent = extent.union(box) }
                fills.append(moved)
            }
            for text in picture.texts where text.view == view.id && (text.annotation != nil || text.mark != nil) && !text.isNotice {
                var moved = text
                moved.origin = mapping.model(text.origin)
                moved.height = text.height * back
                extent = extent.union(Rect2D(min: moved.origin, max: moved.origin))
                texts.append(moved)
            }
        }
        return write(strokes: strokes, texts: texts, fills: fills, extent: extent, style: style)
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
        if stroke.pattern == .centre && stroke.layer != .center { t.add(6, "CENTER") }
        // A layer's own linetype is chained or dashed: a solid stroke on it (a cutting line's thick ends, a small centre
        // mark) says so (DR-3 R6).
        if stroke.pattern == .solid && (stroke.layer == .center || stroke.layer == .hidden) { t.add(6, "Continuous") }
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
            // 128: the linetype pattern runs on through the vertices instead of restarting at each.
            t.add(70, 128)
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
        if text.angle != 0 { t.add(50, degrees(text.angle)) }
        t.add(7, "Standard")
        t.add(100, "AcDbText")
    }

    /// A filled polygon as a fan of `SOLID`s from its first point; each triangle's fourth vertex repeats its third.
    private static func solids(_ fill: SheetFill, owner: String, handles: inout DXFHandles, into t: inout DXFText) {
        guard fill.points.count >= 3 else { return }
        for index in 1..<(fill.points.count - 1) {
            let corners = [fill.points[0], fill.points[index], fill.points[index + 1]]
            t.add(0, "SOLID")
            t.add(5, handles.make())
            t.add(330, owner)
            t.add(100, "AcDbEntity")
            t.add(8, fill.layer.rawValue)
            t.add(100, "AcDbTrace")
            for (slot, point) in (corners + [corners[2]]).enumerated() {
                t.add(10 + slot, point.x)
                t.add(20 + slot, point.y)
                t.add(30 + slot, 0.0)
            }
        }
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
