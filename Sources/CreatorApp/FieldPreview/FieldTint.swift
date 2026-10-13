/// A field sampled at a mesh's vertices (fields spec §6): one value per vertex, in the mesh's order, the smallest and largest
/// finite value sampled (the ramp's automatic range; `nil` when none was finite) and whether the sampling was coarse (D14).
struct FieldTint: Sendable, Equatable {
    var values: [Float]
    var extent: ClosedRange<Double>?
    var isCoarse: Bool
}
