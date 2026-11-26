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
            ForEach(Self.fillGroups(of: fills), id: \.isLost) { group in
                let origin = Vector2(group.bounds.min.x, group.bounds.max.y)
                SheetFillShape(polygons: group.polygons, zoom: zoom, origin: origin)
                    .fill((group.isLost ? warning ?? ink : ink).color)
                    .frame(width: (group.bounds.width * zoom).px, height: (group.bounds.height * zoom).px)
                    .offset(x: (origin.x * zoom).px, y: ((paperHeight - origin.y) * zoom).px)
            }
        }
    }

    /// The fills in two runs, the held ones and the lost ones (those only when there are any), each with its bounds.
    static func fillGroups(of fills: [SheetFill]) -> [(isLost: Bool, polygons: [[Vector2]], bounds: Rect2D)] {
        [false, true].compactMap { lost in
            let chosen = fills.filter { $0.isLost == lost && $0.points.count >= 3 }
            guard let first = chosen.first?.points.first else { return nil }
            var low = first, high = first
            for point in chosen.flatMap(\.points) {
                low = Vector2(Swift.min(low.x, point.x), Swift.min(low.y, point.y))
                high = Vector2(Swift.max(high.x, point.x), Swift.max(high.y, point.y))
            }
            return (lost, chosen.map(\.points), Rect2D(min: low, max: high))
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
                    color: texts[index].isNotice || texts[index].isLost ? warning : ink)
            }
        }
    }
}
