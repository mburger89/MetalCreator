import CreatorGeometry
import CreatorKernel

extension AnnotationComposer {
    /// A balloon (DR-5 R4): the part's item number in a circle at `offset` from the foot, the leader landing like a note's. Lost by
    /// DR-2's rules plus `.partNotShown`: drawn from its last foot with the number followed by "?", or a lone "?" with none.
    static func composeBalloon(
        _ annotation: DrawingAnnotation, _ balloon: Balloon, context: AnnotationContext, remembered: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let part = balloon.leader.target.part ?? context.viewSource
        let digits = part.flatMap { context.items.number(of: $0) }.map { String($0) } ?? "?"
        let label = "Balloon \(digits)"
        var anchors: [AnchorStatus] = []
        var reason: LostReason
        switch context.state {
        case .unlisted(let why):
            return (AnnotationReport(status: .lost(why), label: label), AnnotationPieces())
        case .failed(let why):
            reason = why
        case .annotated:
            let (status, model) = resolve(balloon.leader, context: context)
            anchors = [status]
            if case .lost(let why) = status {
                reason = why
            } else if let model, let mapping = context.mapping {
                return held(annotation, balloon, digits: digits, foot: model, mapping: mapping, context: context)
            } else {
                reason = .noPart
            }
        }
        let report = AnnotationReport(status: .lost(reason), anchors: anchors, label: label)
        return lost(annotation, balloon, digits: digits, report: report, context: context, last: remembered)
    }

    private static func held(
        _ annotation: DrawingAnnotation, _ balloon: Balloon, digits: String, foot: Vector2, mapping: ViewMapping,
        context: AnnotationContext
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let sheetFoot = mapping.sheet(foot)
        let drawing = BalloonLayout.draw(
            number: digits, center: sheetFoot + balloon.offset, foot: sheetFoot, h: context.height, style: context.style)
        let made = tagged(drawing, annotation: annotation.id, context: context, isLost: false)
        let report = AnnotationReport(
            status: .held, anchors: [.held], current: LastGood(values: [], lines: [digits], figure: .leaders([foot])),
            label: "Balloon \(digits)",
            frame: made.frame ?? Rect2D(min: .zero, max: .zero), textCenter: drawing.textCenter)
        return (report, made)
    }

    private static func lost(
        _ annotation: DrawingAnnotation, _ balloon: Balloon, digits: String, report lostReport: AnnotationReport,
        context: AnnotationContext, last: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        var report = lostReport
        guard let mapping = context.mapping else { return (report, AnnotationPieces()) }
        if case .leaders(let points)? = last?.figure, let foot = points.first {
            let sheetFoot = mapping.sheet(foot)
            let drawing = BalloonLayout.draw(
                number: digits + "?", center: sheetFoot + balloon.offset, foot: sheetFoot, h: context.height, style: context.style)
            let made = tagged(drawing, annotation: annotation.id, context: context, isLost: true)
            report.frame = made.frame ?? report.frame
            report.textCenter = drawing.textCenter
            return (report, made)
        }
        // Nothing to draw from: a lone "?" at the view frame's bottom left.
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
}
