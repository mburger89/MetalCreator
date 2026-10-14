import CreatorGeometry

extension Field {
    /// The plane this field is laid out on, if it has one: the plane of the first linear gradient or image in the expression,
    /// searched depth first from the left (fields spec §6 starts the preview's slice plane there). A distance, a radial
    /// gradient, noise or a constant has none, so an expression made only of those has none. No `default`: a new case must say
    /// whether it carries a plane.
    public var ownPlane: Plane? {
        switch self {
        case .linearGradient(let plane, _), .image(_, let plane, _, _, _):
            plane
        case .constant, .distance, .radialGradient, .noise, .implicit:
            nil
        case .add, .multiply, .minimum, .maximum, .remap, .clamp, .smoothMinimum:
            children.lazy.compactMap(\.ownPlane).first
        }
    }
}
