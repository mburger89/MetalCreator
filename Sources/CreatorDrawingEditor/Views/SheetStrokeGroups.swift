import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// A run of strokes drawn in paper space: one shape per distinct (width, pattern), each framed tightly to its own bounds so
/// a zoomed sheet never asks for a paper-sized path. Paper space is the sheet's top left at (0, 0) in points
/// (sheet millimetres times `zoom`, y down). Widths are at least one point; dashes are sheet millimetres times `zoom`
/// (plan R12). Pure data: the layers that hold it are `.equatable()`.
struct SheetStrokeGroups: Component {
    let strokes: [SheetStroke]
    let zoom: Double
    let paperHeight: Double
    let ink: HexColor
    let style: DrawingStyle
    /// Filled polygons (arrowheads), drawn after the strokes.
    var fills: [SheetFill] = []
    /// What a lost annotation's strokes and fills are drawn in (plan R15); the ink when none is given.
    var warning: HexColor?

    struct Key: Hashable {
        var width: Double
        var pattern: StrokePattern
        var isLost = false
    }

    /// The strokes by (width, pattern), in first-seen order.
    static func groups(of strokes: [SheetStroke]) -> [(key: Key, segments: [SheetSegment], bounds: Rect2D)] {
        var order: [Key] = []
        var found: [Key: (segments: [SheetSegment], bounds: Rect2D)] = [:]
        for stroke in strokes where !stroke.segments.isEmpty {
            let key = Key(width: stroke.width, pattern: stroke.pattern, isLost: stroke.isLost)
            if var entry = found[key] {
                entry.segments += stroke.segments
                entry.bounds = entry.bounds.union(stroke.bounds)
                found[key] = entry
            } else {
                order.append(key)
                found[key] = (stroke.segments, stroke.bounds)
            }
        }
        return order.compactMap { key in found[key].map { (key, $0.segments, $0.bounds) } }
    }

    /// One shape per fill, each its own path, so overlapping fills never cancel whatever their winding (drawings minors R4).
    func fillShapes() -> [(shape: SheetFillShape, isLost: Bool, bounds: Rect2D)] {
        fills.compactMap { fill in
            guard fill.points.count >= 3, let bounds = Rect2D(points: fill.points) else { return nil }
            let origin = Vector2(bounds.min.x, bounds.max.y)
            return (SheetFillShape(polygon: fill.points, zoom: zoom, origin: origin), fill.isLost, bounds)
        }
    }

    static func strokeStyle(_ key: Key, zoom: Double, style: DrawingStyle) -> StrokeStyle {
        let dash: [Pixels]
        switch key.pattern {
        case .solid: dash = []
        case .hidden: dash = [(style.hiddenDash * zoom).px, (style.hiddenGap * zoom).px]
        case .centre: dash = style.centreDash.map { ($0 * zoom).px }
        }
        return StrokeStyle(lineWidth: Swift.max(key.width * zoom, 1).px, lineCap: .butt, lineJoin: .round, dash: dash)
    }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.groups(of: strokes).enumerated()), id: \.offset) { pair in
                let group = pair.element
                let pad = 2 + Swift.max(group.key.width * zoom, 1)
                let origin = Vector2(group.bounds.min.x - pad / zoom, group.bounds.max.y + pad / zoom)
                SheetStrokeShape(segments: group.segments, zoom: zoom, origin: origin)
                    .stroke((group.key.isLost ? warning ?? ink : ink).color, style: Self.strokeStyle(group.key, zoom: zoom, style: style))
                    .frame(width: (group.bounds.width * zoom + 2 * pad).px, height: (group.bounds.height * zoom + 2 * pad).px)
                    .offset(x: (origin.x * zoom).px, y: ((paperHeight - origin.y) * zoom).px)
            }
            ForEach(Array(fillShapes().enumerated()), id: \.offset) { pair in
                let drawn = pair.element
                let origin = Vector2(drawn.bounds.min.x, drawn.bounds.max.y)
                drawn.shape
                    .fill((drawn.isLost ? warning ?? ink : ink).color)
                    .frame(width: (drawn.bounds.width * zoom).px, height: (drawn.bounds.height * zoom).px)
                    .offset(x: (origin.x * zoom).px, y: ((paperHeight - origin.y) * zoom).px)
            }
        }
    }
}

/// Lettering in paper space: each text's top left sits `SheetTextView.lift` above its baseline.
struct SheetTexts: Component {
    let texts: [SheetText]
    let zoom: Double
    let paperHeight: Double
    let ink: HexColor
    let warning: HexColor

    var content: some ElementGroup {
        let reference = SheetTextZoom.reference(for: zoom)
        // Angle 0, so a text of 2π gives MetalUI no rotation to resample under (R8).
        let upright = texts.filter { SheetTextZoom.isScaled($0, zoom: zoom) }.map { text -> SheetText in
            var copy = text
            copy.angle = 0
            return copy
        }
        let rotated = texts.filter { !SheetTextZoom.isScaled($0, zoom: zoom) }
        return ZStack(alignment: .topLeading) {
            if !upright.isEmpty {
                // Laid out at the band's reference zoom and scaled from the paper's top left (zoom-text plan R1, R3).
                ZStack(alignment: .topLeading) {
                    SheetUprightTexts(texts: upright, reference: reference, paperHeight: paperHeight, ink: ink, warning: warning)
                        .equatable()
                }
                .scaleEffect(zoom / reference, anchor: .topLeading)
            }
            ForEach(rotated.indices, id: \.self) { index in
                SheetTextView(
                    text: rotated[index], zoom: zoom, paperHeight: paperHeight,
                    color: rotated[index].isNotice || rotated[index].isLost ? warning : ink)
            }
        }
    }
}
