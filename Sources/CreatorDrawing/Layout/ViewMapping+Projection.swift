import CreatorGeometry
import CreatorKernel

extension ViewMapping {
    /// The mapping of a view whose projection's bounds centre lands on `center` at `scale`; `nil` without bounds.
    public static func of(projection: Projection2D, center: Vector2, scale: Double) -> ViewMapping? {
        guard let bounds = projection.bounds else { return nil }
        return ViewMapping(scale: scale, offset: center - bounds.center * scale)
    }
}
