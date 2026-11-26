import CreatorGeometry
import CreatorKernel

extension AnnotationEvaluator {
    /// A symbol on a line of its view (plan R2, R11): the line resolved, judged for the symbol and its foot found. `nil` for a
    /// symbol on a dimension, which the second composing pass hangs on its dimension's drawing, and for any other kind.
    static func symbol(
        _ annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat, parts: [PartSpan]
    ) -> EvaluatedAnnotation? {
        guard case .feature(let end)? = annotation.symbolAttachment, let kind = annotation.symbolKind else { return nil }
        func lost(_ reason: LostReason) -> EvaluatedAnnotation {
            EvaluatedAnnotation(anchors: [.lost(reason)], outcome: .failure(reason))
        }
        switch DrawingAnchorResolver.resolve(end.target, in: topology, frame: frame, parts: parts) {
        case .lost(let reason): return lost(reason)
        case .held(let geometry, _, _):
            if let reason = unsuitable(geometry, for: kind, frame: frame) { return lost(reason) }
            switch SymbolFoot.of(geometry, hint: end.hint, frame: frame) {
            case .failure(let reason): return lost(reason)
            case .success(let found):
                let text = plainText(of: annotation, format: format)
                let current = LastGood(values: [], lines: [text], figure: .attachment(foot: found.foot, along: found.along))
                var held = HeldAnnotation(labels: [], current: current, label: text)
                if let segment = found.segment { held.edgeEnds = [segment.0, segment.1] }
                return EvaluatedAnnotation(anchors: [.held], outcome: .success(held))
            }
        }
    }

    /// Why held geometry no longer suits a symbol (plan R2): a datum or surface symbol needs a straight line, a frame a straight
    /// line or a circle seen face on, and no symbol stands on a line now seen end on.
    private static func unsuitable(_ geometry: AnchorGeometry, for kind: SymbolKind, frame: ProjectionFrame) -> LostReason? {
        switch geometry {
        case .segment(let a, let b):
            return DrawingPick.isSeenEndOn(b - a, direction: frame.direction) ? .turnedAway : nil
        case .cylinder(_, let axis, _, _):
            return abs(axis.dot(frame.direction)) > 1e-9 * axis.length ? .turnedAway : nil
        case .circle(_, let axis, _, _):
            guard kind == .frame else { return .notStraight }
            return abs(axis.dot(frame.direction)) >= 1 - 1e-9 ? nil : .turnedAway
        case .point, .other:
            return kind == .frame ? .notLineOrCircle : .notStraight
        }
    }

    /// A symbol's text for lists, warnings and a lost symbol's report (plan R11).
    static func plainText(of annotation: DrawingAnnotation, format: NumberFormat) -> String {
        switch annotation.kind {
        case .datumFeature(let datum): datum.plainText
        case .featureControl(let frame): frame.plainText(format: format)
        case .surfaceTexture(let texture): texture.plainText(format: format)
        default: ""
        }
    }
}
