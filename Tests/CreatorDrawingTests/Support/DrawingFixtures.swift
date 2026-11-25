import CreatorGeometry

@testable import CreatorDrawing

/// A fixed A4 sheet (portrait, 210 x 297 mm) with a box view and a cylinder view and a title block, built by hand from
/// strokes and texts: no kernel. Shared by the PDF and DXF tests.
enum DrawingFixtures {
    static let titleBlockText = "Ø20 ±0.1 µm 90°"

    static func text(_ string: String, at origin: Vector2, height: Double, view: ViewID? = nil) -> SheetText {
        SheetText(run: DrawingText.layout(string, height: height), original: string, origin: origin, height: height, view: view)
    }

    static func a4Sheet() -> SheetPicture {
        let style = DrawingStyle.iso
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.strokes.append(
            SheetStroke(
                segments: [.polyline([Vector2(20, 10), Vector2(200, 10), Vector2(200, 287), Vector2(20, 287), Vector2(20, 10)])],
                width: style.frame, layer: .frame))
        // The box view: a 40 x 30 rectangle with a hidden inner line.
        picture.strokes.append(
            SheetStroke(
                segments: [.polyline([Vector2(40, 200), Vector2(80, 200), Vector2(80, 230), Vector2(40, 230), Vector2(40, 200)])],
                width: style.thick, layer: .visible))
        picture.strokes.append(
            SheetStroke(segments: [.line(Vector2(45, 205), Vector2(75, 205))], width: style.thin, pattern: .hidden, layer: .hidden))
        // The cylinder view: its end as a circle with centre lines, and a side outline.
        picture.strokes.append(
            SheetStroke(
                segments: [.arc(center: Vector2(130, 215), radius: 10, start: 0, sweep: 2 * .pi)], width: style.thick,
                layer: .visible))
        picture.strokes.append(
            SheetStroke(
                segments: [.line(Vector2(115, 215), Vector2(145, 215)), .line(Vector2(130, 200), Vector2(130, 230))],
                width: style.thin, layer: .center))
        let halfEllipse = SheetSegment.ellipse(
            center: Vector2(130, 150), majorAxis: Vector2(1, 0), majorRadius: 12, minorRadius: 5, start: 0, sweep: .pi)
        picture.strokes.append(
            SheetStroke(
                segments: [halfEllipse],
                width: style.thick, layer: .visible))
        picture.texts.append(text("A", at: Vector2(40, 235), height: style.viewLabelHeight))
        picture.texts.append(text("Ω-Bracket →", at: Vector2(25, 20), height: style.titleHeight))
        picture.texts.append(text(titleBlockText, at: Vector2(25, 40), height: style.notesHeight(for: .a4)))
        picture.texts.append(text("a(b)c\\d", at: Vector2(25, 50), height: style.notesHeight(for: .a4)))
        return picture
    }
}
