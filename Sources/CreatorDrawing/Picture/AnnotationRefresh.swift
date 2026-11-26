import CreatorKernel

/// Re-reads an annotation's newest held values without projecting or laying anything out (plan R26).
public enum AnnotationRefresh {
    /// What the composer would report as the annotation's `current`, or nil when it is lost. A note is never refreshed here:
    /// its leaders' last points come from composes, which have the projected lines, and a symbol on a dimension is skipped
    /// likewise (it draws from its dimension and has no figure of its own, plan R11); a symbol on a line is re-read like a
    /// dimension, its foot and tangent as the `.attachment` figure.
    public static func lastGood(
        for annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat,
        standard: DrawingStandard
    ) -> LastGood? {
        var format = format
        format.standard = standard
        guard let evaluated = AnnotationEvaluator.evaluate(annotation, topology: topology, frame: frame, format: format),
            case .success(let held) = evaluated.outcome
        else { return nil }
        return held.current
    }

    /// Why `annotation` would be lost against `topology`, or nil when it would be held (and for a note, which is never judged here).
    public static func lostReason(
        of annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat,
        standard: DrawingStandard
    ) -> LostReason? {
        var format = format
        format.standard = standard
        guard let evaluated = AnnotationEvaluator.evaluate(annotation, topology: topology, frame: frame, format: format),
            case .failure(let reason) = evaluated.outcome
        else { return nil }
        return reason
    }
}
