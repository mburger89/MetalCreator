import CreatorGeometry
import CreatorKernel
import Foundation

extension AnnotationComposer {
    /// A note: its lines at `linePitch x h`, and each leader resolved alone (plan R14, R15). A leader whose target is lost draws
    /// to its remembered point and the note itself stays held.
    static func composeNote(
        _ annotation: DrawingAnnotation, _ note: DrawingNote, context: AnnotationContext, remembered: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let h = context.height
        let style = context.style
        let origin = context.center + note.position
        let lines = note.text.components(separatedBy: "\n")
        var out = AnnotationPieces()
        var widest = 0.0
        var firstCenter: Vector2?
        for (index, line) in lines.enumerated() {
            let run = DrawingText.layout(line, height: h)
            let baseline = Vector2(origin.x, origin.y - h - Double(index) * style.linePitch * h)
            widest = Swift.max(widest, run.width)
            if index == 0 { firstCenter = Vector2(origin.x + run.width / 2, baseline.y + h / 2) }
            out.texts.append(
                SheetText(
                    run: run, original: line, origin: baseline, height: h, layer: .text, view: context.view,
                    annotation: annotation.id))
        }
        let bottom = origin.y - h - Double(Swift.max(lines.count - 1, 0)) * style.linePitch * h
        var frame = Rect2D(min: Vector2(origin.x, bottom), max: Vector2(origin.x + widest, origin.y))
        let attachY = origin.y - h / 2
        let block = Vector2(origin.x + widest / 2, attachY)

        var statuses: [AnchorStatus] = []
        var stored: [Vector2] = []
        let lastPoints: [Vector2]
        if case .leaders(let points)? = remembered?.figure { lastPoints = points } else { lastPoints = [] }
        for (index, leader) in note.leaders.enumerated() {
            let (status, model) = resolve(leader, context: context)
            statuses.append(status)
            let fallback = index < lastPoints.count ? lastPoints[index] : leader.hint
            let point = model ?? fallback
            stored.append(point)
            guard let tip = tipOnSheet(of: leader, model: model, fallback: fallback, context: context) else { continue }
            let leftOfBlock = tip.x < block.x
            let attach = Vector2(leftOfBlock ? origin.x : origin.x + widest, attachY)
            let knee = Vector2(attach.x + (leftOfBlock ? -style.shoulder : style.shoulder), attachY)
            let drawing = SheetDimensionLayout.leader(
                tip: tip, knee: knee, side: leftOfBlock ? .right : .left, style: style)
            let tagged = tagged(drawing, annotation: annotation.id, context: context, isLost: false)
            out.strokes += tagged.strokes
            out.fills += tagged.fills
            if let more = tagged.frame { frame = frame.union(more) }
        }
        out.frame = frame
        // Without a mapping a view note's leader points can't be stored, so nothing is remembered from it; and a view that
        // is not annotated says nothing about the leaders' anchors (plan R25).
        let current = context.mapping == nil ? nil : LastGood(values: [], lines: lines, figure: .leaders(stored))
        var isAnnotated = false
        if case .annotated = context.state { isAnnotated = true }
        let report = AnnotationReport(
            status: .held, anchors: isAnnotated ? statuses : [], current: current, label: lines.first ?? "", frame: frame,
            textCenter: firstCenter)
        return (report, out)
    }

    /// A leader end's status and, when it holds, its point in the note's own plane (the view's model plane, or the sheet).
    static func resolve(_ leader: LeaderEnd, context: AnnotationContext) -> (AnchorStatus, Vector2?) {
        switch leader.target {
        case .point(let point):
            // A view note's free end is sheet millimetres from the view's centre; stored in the model plane.
            let sheet = context.view == nil ? point : context.center + point
            return (.held, context.mapping.map { $0.model(sheet) } ?? sheet)
        default:
            guard case .annotated(let topology, let frame, let parts) = context.state, let projection = context.projection else {
                return (.held, nil)
            }
            let resolution = DrawingAnchorResolver.resolve(leader.target, in: topology, frame: frame, parts: parts)
            switch resolution {
            case .lost(let reason): return (.lost(reason), nil)
            case .held(let geometry, let edges, _):
                return (.held, landing(geometry, edges: edges, hint: leader.hint, projection: projection, frame: frame))
            }
        }
    }

    /// Where a leader ends on the sheet.
    static func tipOnSheet(of leader: LeaderEnd, model: Vector2?, fallback: Vector2, context: AnnotationContext) -> Vector2? {
        if case .point(let point) = leader.target { return context.view == nil ? point : context.center + point }
        guard let mapping = context.mapping else { return nil }
        return mapping.sheet(model ?? fallback)
    }

    /// The leader's end in the model plane: the point of the edge's projected lines nearest the hint, else the geometry's own.
    private static func landing(
        _ geometry: AnchorGeometry, edges: [EdgeID], hint: Vector2, projection: Projection2D, frame: ProjectionFrame
    ) -> Vector2? {
        switch geometry {
        case .point(let p): return frame.place(p)
        case .other(let midpoint): return frame.place(midpoint)
        case .cylinder(let axisPoint, _, _, _): return frame.place(axisPoint)
        case .segment, .circle:
            var best: (point: Vector2, distance: Double)?
            for line in projection.lines {
                guard case .edge(let id)? = line.source, edges.contains(id) else { continue }
                let near = CurveNearest.point(on: line.curve, to: hint)
                let distance = (near - hint).length
                if distance < (best?.distance ?? .infinity) { best = (near, distance) }
            }
            if let best { return best.point }
            return exactNearest(geometry, hint: hint, frame: frame)
        }
    }

    private static func exactNearest(_ geometry: AnchorGeometry, hint: Vector2, frame: ProjectionFrame) -> Vector2? {
        switch geometry {
        case .segment(let a, let b): return CurveNearest.point(on: .line(frame.place(a), frame.place(b)), to: hint)
        case .circle(let center, _, let radius, _):
            let c = frame.place(center)
            return CurveNearest.point(on: .arc(center: c, radius: radius, start: 0, sweep: 2 * .pi), to: hint)
        default: return nil
        }
    }
}

/// The point of a projected curve nearest a point, in the model plane.
enum CurveNearest {
    private static let samples = 180

    static func point(on curve: ProjectedCurve, to hint: Vector2) -> Vector2 {
        switch curve {
        case let .line(a, b): return onSegment(a, b, hint)
        case let .polyline(points):
            var best = points.first ?? hint
            for pair in zip(points, points.dropFirst()) {
                let near = onSegment(pair.0, pair.1, hint)
                if (near - hint).length < (best - hint).length { best = near }
            }
            return best
        case let .arc(center, radius, start, sweep):
            let full = 2 * Double.pi
            let toward = hint - center
            let angle = atan2(toward.y, toward.x)
            var delta = sweep >= 0 ? angle - start : start - angle
            delta = delta.truncatingRemainder(dividingBy: full)
            if delta < 0 { delta += full }
            func at(_ t: Double) -> Vector2 { center + Vector2(cos(t), sin(t)) * radius }
            if abs(sweep) >= full - 1e-9 || delta <= abs(sweep) { return at(angle) }
            let ends = [at(start), at(start + sweep)]
            return (ends[0] - hint).length <= (ends[1] - hint).length ? ends[0] : ends[1]
        case let .ellipse(center, axis, major, minor, start, sweep):
            let up = Vector2(-axis.y, axis.x)
            var best = center + axis * (cos(start) * major) + up * (sin(start) * minor)
            for step in 0...samples {
                let t = start + sweep * Double(step) / Double(samples)
                let p = center + axis * (cos(t) * major) + up * (sin(t) * minor)
                if (p - hint).length < (best - hint).length { best = p }
            }
            return best
        }
    }

    private static func onSegment(_ a: Vector2, _ b: Vector2, _ p: Vector2) -> Vector2 {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 1e-18 else { return a }
        let t = Swift.min(1, Swift.max(0, ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared))
        return a + d * t
    }
}
