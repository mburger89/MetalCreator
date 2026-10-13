/// What a field's numbers are measured in, for the preview's legend (fields spec §6: "units where the field has them (mm for
/// distances)"). Most fields are plain numbers.
public enum FieldUnit: Sendable, Equatable {
    case none
    case millimetres
}
