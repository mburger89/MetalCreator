import CreatorGeometry
import CreatorKernel
import Foundation

extension AnnotationComposer {
    static let symbolOnDimensionSentence = "This symbol hangs on a dimension; reattach the dimension and the symbol follows it."

    // MARK: On a line

    /// A datum, frame or surface symbol on a line of its view (plan R2, R11). A lost one is drawn from its last figure with every
    /// piece marked lost and a "?" at its top right; with no last figure it is DR-2's lone "?".
    static func composeSymbol(
        _ annotation: DrawingAnnotation, context: AnnotationContext, format: NumberFormat, remembered: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let text = AnnotationEvaluator.plainText(of: annotation, format: format)
        if case .dimension? = annotation.symbolAttachment {
            return (AnnotationReport(status: .lost(.missing), label: text), AnnotationPieces())
        }
        switch context.state {
        case .unlisted(let reason):
            return (AnnotationReport(status: .lost(reason), label: text), AnnotationPieces())
        case .failed(let reason):
            return lostSymbol(annotation, because: (reason, []), context: context, format: format, last: remembered)
        case .annotated(let topology, let frame, let parts):
            // R17: an isometric view takes no symbols, so one placed before the view turned is lost, never drawn.
            if context.isPictorial, case .feature? = annotation.symbolAttachment {
                return lostSymbol(
                    annotation, because: (.refused(DrawingPick.symbolIsometricSentence), []), context: context, format: format,
                    last: remembered)
            }
            guard let evaluated = AnnotationEvaluator.evaluate(
                annotation, topology: topology, frame: frame, format: format, parts: parts)
            else {
                return (AnnotationReport(status: .lost(.noPart), label: text), AnnotationPieces())
            }
            switch evaluated.outcome {
            case .failure(let reason):
                return lostSymbol(
                    annotation, because: (reason, evaluated.anchors), context: context, format: format, last: remembered)
            case .success(let held):
                var pieces = AnnotationPieces()
                if let mapping = context.mapping, case .attachment(let foot, let along) = held.current.figure {
                    let drawing = onLine(
                        annotation, at: (foot, along), ends: held.edgeEnds, mapping: mapping, context: context, format: format)
                    pieces = tagged(drawing, annotation: annotation.id, context: context, isLost: false)
                }
                let report = AnnotationReport(
                    status: .held, anchors: evaluated.anchors, current: held.current, label: held.label,
                    frame: pieces.frame ?? Rect2D(min: .zero, max: .zero))
                return (report, pieces)
            }
        }
    }

    /// What `annotation` draws standing on a line at `foot` (model plane, the unit tangent `along`).
    private static func onLine(
        _ annotation: DrawingAnnotation, at place: (foot: Vector2, along: Vector2), ends: [Vector2], mapping: ViewMapping,
        context: AnnotationContext, format: NumberFormat
    ) -> AnnotationDrawing {
        let (foot, along) = place
        let h = context.height
        let sheetFoot = mapping.sheet(foot)
        let sheetAlong = along * (along.length > 0 ? 1 / along.length : 1)
        switch annotation.kind {
        case .datumFeature(let datum):
            let edgeEnds = ends.count == 2 ? (mapping.sheet(ends[0]), mapping.sheet(ends[1])) : nil
            return DatumLayout.onLine(
                letter: datum.letter, foot: sheetFoot, along: sheetAlong, distance: datum.distance, edgeEnds: edgeEnds, h: h,
                style: context.style)
        case .featureControl(let frame):
            let topLeft = sheetFoot + frame.offset
            var drawing = framed(frame, topLeft: topLeft, context: context, format: format)
            let size = FrameLayout.size(of: frame, h: h, format: format, standard: context.standard)
            let rect = Rect2D(min: Vector2(topLeft.x, topLeft.y - size.y), max: Vector2(topLeft.x + size.x, topLeft.y))
            let leader = FrameLayout.leader(
                from: sheetFoot, toFrameAt: rect, rowHeight: SymbolStyle.of(context.standard).frameHeight * h, style: context.style)
            drawing.segments += leader.segments
            drawing.fills += leader.fills
            drawing.texts += leader.texts
            drawing.fitFrame()
            return drawing
        case .surfaceTexture(let texture):
            return SurfaceLayout.draw(texture, foot: sheetFoot, along: sheetAlong, h: h, format: format, style: context.style)
        default:
            return AnnotationDrawing()
        }
    }

    private static func framed(
        _ frame: FeatureControlFrame, topLeft: Vector2, context: AnnotationContext, format: NumberFormat
    ) -> AnnotationDrawing {
        FrameLayout.draw(frame, topLeft: topLeft, h: context.height, format: format, standard: context.standard)
    }

    /// A lost symbol: its last figure drawn lost with a "?" right of its top right, or the lone "?" of DR-2.
    private static func lostSymbol(
        _ annotation: DrawingAnnotation, because lost: (reason: LostReason, anchors: [AnchorStatus]), context: AnnotationContext,
        format: NumberFormat, last: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let text = AnnotationEvaluator.plainText(of: annotation, format: format)
        var report = AnnotationReport(status: .lost(lost.reason), anchors: lost.anchors, label: text)
        guard let mapping = context.mapping else { return (report, AnnotationPieces()) }
        if case .attachment(let foot, let along)? = last?.figure {
            let drawing = onLine(annotation, at: (foot, along), ends: [], mapping: mapping, context: context, format: format)
            var pieces = tagged(drawing, annotation: annotation.id, context: context, isLost: true)
            if let frame = pieces.frame {
                pieces = marked(pieces, after: frame, annotation: annotation, context: context)
                report.frame = pieces.frame ?? frame
                return (report, pieces)
            }
        }
        let run = DrawingText.layout("?", height: context.height)
        let origin = context.viewFrame.min
        var out = AnnotationPieces()
        out.texts = [
            SheetText(
                run: run, original: "?", origin: origin, height: context.height, layer: .dimension, view: context.view,
                annotation: annotation.id, isLost: true),
        ]
        out.frame = Rect2D(min: origin, max: origin + Vector2(run.width, context.height))
        report.frame = out.frame ?? report.frame
        return (report, out)
    }

    /// `pieces` with a lost "?" `textGap` right of the top right of `frame`.
    private static func marked(
        _ pieces: AnnotationPieces, after frame: Rect2D, annotation: DrawingAnnotation, context: AnnotationContext
    ) -> AnnotationPieces {
        var out = pieces
        let run = DrawingText.layout("?", height: context.height)
        let origin = Vector2(frame.max.x + context.style.textGap, frame.max.y - context.height)
        out.texts.append(
            SheetText(
                run: run, original: "?", origin: origin, height: context.height, layer: .dimension, view: context.view,
                annotation: annotation.id, isLost: true))
        out.frame = frame.union(Rect2D(min: origin, max: origin + Vector2(run.width, context.height)))
        return out
    }

    // MARK: On a dimension

    /// A frame or datum symbol on a dimension or hole callout of its view (plan R2, R5, R11), drawn from the dimension's own
    /// report (its first label's rectangle and dimension line). It is held when the dimension is, lost with its reason and drawn
    /// lost when the dimension is lost but drew something, and listed alone when the dimension drew nothing. `below` is the
    /// lowest y that frames and datums already stacked on that dimension reach; the result's `bottom` is the new one.
    static func composeOnDimension(
        _ annotation: DrawingAnnotation, host: AnnotationReport?, context: AnnotationContext, format: NumberFormat, below: Double?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces, bottom: Double?) {
        let text = AnnotationEvaluator.plainText(of: annotation, format: format)
        guard let host else { return (AnnotationReport(status: .lost(.missing), label: text), AnnotationPieces(), below) }
        guard let rect = host.labelRect, context.mapping != nil else {
            let status: AnnotationStatus = host.isLost ? host.status : .lost(.noPart)
            return (AnnotationReport(status: status, label: text), AnnotationPieces(), below)
        }
        let isLost = host.isLost
        let h = context.height
        var drawing: AnnotationDrawing
        var stacks = true
        switch annotation.kind {
        case .featureControl(let frame):
            let top = (below ?? rect.min.y) - context.style.textGap
            drawing = framed(frame, topLeft: Vector2(rect.min.x, top) + frame.offset, context: context, format: format)
        case .datumFeature(let datum):
            if let tips = host.dimensionLine, tips.count == 2 {
                let end = Swift.min(Swift.max(datum.dimensionEnd, 0), 1)
                stacks = false
                drawing = DatumLayout.onDimensionLine(
                    letter: datum.letter, end: tips[end], other: tips[1 - end], distance: datum.distance, h: h, style: context.style)
            } else {
                let y = below.map { $0 - context.style.textGap } ?? rect.min.y
                drawing = DatumLayout.hanging(
                    letter: datum.letter, below: Vector2((rect.min.x + rect.max.x) / 2, y), distance: datum.distance, h: h,
                    style: context.style)
            }
        default:
            return (AnnotationReport(status: host.status, label: text), AnnotationPieces(), below)
        }
        drawing.fitFrame()
        let pieces = tagged(drawing, annotation: annotation.id, context: context, isLost: isLost)
        let frame = pieces.frame ?? Rect2D(min: .zero, max: .zero)
        let report = AnnotationReport(status: host.status, label: text, frame: frame)
        return (report, pieces, stacks ? Swift.min(below ?? frame.min.y, frame.min.y) : below)
    }
}
