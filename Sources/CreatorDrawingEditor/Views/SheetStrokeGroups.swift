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

    struct Key: Hashable {
        var width: Double
        var pattern: StrokePattern
    }

    /// The strokes by (width, pattern), in first-seen order.
    static func groups(of strokes: [SheetStroke]) -> [(key: Key, segments: [SheetSegment], bounds: Rect2D)] {
        var order: [Key] = []
        var found: [Key: (segments: [SheetSegment], bounds: Rect2D)] = [:]
        for stroke in strokes where !stroke.segments.isEmpty {
            let key = Key(width: stroke.width, pattern: stroke.pattern)
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

    static func strokeStyle(_ key: Key, zoom: Double, style: DrawingStyle) -> StrokeStyle {
        let dash: [Pixels] = key.pattern == .hidden ? [(style.hiddenDash * zoom).px, (style.hiddenGap * zoom).px] : []
        return StrokeStyle(lineWidth: Swift.max(key.width * zoom, 1).px, lineCap: .butt, lineJoin: .round, dash: dash)
    }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.groups(of: strokes).enumerated()), id: \.offset) { pair in
                let group = pair.element
                let pad = 2 + Swift.max(group.key.width * zoom, 1)
                let origin = Vector2(group.bounds.min.x - pad / zoom, group.bounds.max.y + pad / zoom)
                SheetStrokeShape(segments: group.segments, zoom: zoom, origin: origin)
                    .stroke(ink.color, style: Self.strokeStyle(group.key, zoom: zoom, style: style))
                    .frame(width: (group.bounds.width * zoom + 2 * pad).px, height: (group.bounds.height * zoom + 2 * pad).px)
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
        ZStack(alignment: .topLeading) {
            ForEach(texts.indices, id: \.self) { index in
                SheetTextView(
                    text: texts[index], zoom: zoom, paperHeight: paperHeight,
                    color: texts[index].isNotice ? warning : ink)
            }
        }
    }
}
