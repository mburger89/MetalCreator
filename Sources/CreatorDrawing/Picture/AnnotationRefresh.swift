import CreatorKernel

// The plan fixes both signatures (DR-5 Task 3): the view's spans and kind travel with the annotation's topology.
// swiftlint:disable function_parameter_count
/// Re-reads an annotation's newest held values without projecting or laying anything out (plan R26).
public enum AnnotationRefresh {
    /// Runs `body`, in which every `lastGood` and `lostReason` call over ONE topology shares the restricted part topologies: the
    /// pass's cache, bound for the call and dropped when it returns (DR-5 minors R15). Make a pass per topology, never across two.
    public static func pass<T>(_ body: () -> T) -> T { SpanScopes.withFreshCache(body) }

    /// What the composer would report as the annotation's `current`, or nil when it is lost. A note is never refreshed here:
    /// its leaders' last points come from composes, which have the projected lines, and a symbol on a dimension is skipped
    /// likewise (it draws from its dimension and has no figure of its own, plan R11); a symbol on a line is re-read like a
    /// dimension, its foot and tangent as the `.attachment` figure.
    public static func lastGood(
        for annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat,
        standard: DrawingStandard, parts: [PartSpan], isPictorial: Bool
    ) -> LastGood? {
        guard !(isPictorial && AnnotationRefresh.isPictorialExempt(annotation)) else { return nil }
        var format = format
        format.standard = standard
        guard let evaluated = AnnotationEvaluator.evaluate(annotation, topology: topology, frame: frame, format: format, parts: parts),
            case .success(let held) = evaluated.outcome
        else { return nil }
        return held.current
    }

    /// Why `annotation` would be lost against `topology`, or nil when it would be held (and for a note, which is never judged here).
    public static func lostReason(
        of annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat,
        standard: DrawingStandard, parts: [PartSpan], isPictorial: Bool
    ) -> LostReason? {
        guard !(isPictorial && AnnotationRefresh.isPictorialExempt(annotation)) else { return nil }
        var format = format
        format.standard = standard
        guard let evaluated = AnnotationEvaluator.evaluate(annotation, topology: topology, frame: frame, format: format, parts: parts),
            case .failure(let reason) = evaluated.outcome
        else { return nil }
        return reason
    }
}

// swiftlint:enable function_parameter_count

extension AnnotationRefresh {
    /// A view with no true measuring plane (an isometric one) takes no dimension or symbol (DR-4 R17: a dimension, datum feature, feature control frame or surface texture): a
    /// held one of those is never refreshed, so a symbol lost in a view turned isometric stops refreshing its foot (DR-5 R21).
    static func isPictorialExempt(_ annotation: DrawingAnnotation) -> Bool {
        switch annotation.kind {
        case .dimension, .datumFeature, .featureControl, .surfaceTexture: true
        default: false
        }
    }
}
