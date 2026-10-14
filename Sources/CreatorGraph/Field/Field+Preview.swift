import CreatorGeometry

/// What the field previews ask of a field (fields spec §6). Each is an exhaustive `switch` with no `default`, so a case added
/// later is a compile error here until it says what it is. The slice's own plane is `Field.ownPlane` (Field+OwnPlane).
extension Field {
    /// Whether sampling needs the kernel: a distance to a solid, faces or edges, anywhere in the expression.
    public var measuresWithKernel: Bool {
        switch self {
        case .distance(.kernel, _):
            true
        case .distance, .constant, .linearGradient, .radialGradient, .noise, .image, .implicit:
            false
        case .add, .multiply, .minimum, .maximum, .remap, .clamp, .smoothMinimum:
            children.contains { $0.measuresWithKernel }
        }
    }

    /// Whether the ramp centres its middle colour on 0 (fields spec §6): a signed distance to a solid, the smaller or larger of
    /// two such, or one held to a range.
    public var isSignedDistance: Bool {
        switch self {
        case .distance(.kernel(.solid), signed: true), .implicit:
            true
        case .minimum(let a, let b), .maximum(let a, let b), .smoothMinimum(let a, let b, _):
            a.isSignedDistance && b.isSignedDistance
        case .clamp(let inner, _, _):
            inner.isSignedDistance
        case .constant, .distance, .linearGradient, .radialGradient, .noise, .image, .add, .multiply, .remap:
            false
        }
    }

    /// What the field's numbers are measured in: a distance is in millimetres, and so is a distance held to a range or combined
    /// with a plain number or another distance by Add, Min / Max or Smooth Blend. A product, a remap and everything else are
    /// plain numbers.
    public var unit: FieldUnit {
        switch self {
        case .distance, .implicit:
            .millimetres
        case .add(let a, let b), .minimum(let a, let b), .maximum(let a, let b), .smoothMinimum(let a, let b, _):
            Self.combinedUnit(a, b)
        case .clamp(let inner, _, _):
            inner.unit
        case .constant, .linearGradient, .radialGradient, .noise, .image, .multiply, .remap:
            .none
        }
    }

    /// The unit of a sum or extremum of two fields: a plain constant takes the other's, equal units stay, a mixture has none.
    private static func combinedUnit(_ a: Field, _ b: Field) -> FieldUnit {
        if case .constant = a { return b.unit }
        if case .constant = b { return a.unit }
        return a.unit == b.unit ? a.unit : .none
    }
}
