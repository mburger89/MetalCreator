import CreatorGraph

/// What the legend draws (fields spec §6): the ramp's range (`nil` before anything is sampled or when no value was a number),
/// the unit of the numbers, the toggles' state, whether the sampling was coarse, and the kernel's words if it failed.
struct FieldLegend: Equatable {
    var range: FieldPreviewRange?
    var unit: FieldUnit
    var isCoarse: Bool
    var usesUnitRange: Bool
    var choice: SliceChoice
    var hasOwnPlane: Bool
    var failure: String?
}
