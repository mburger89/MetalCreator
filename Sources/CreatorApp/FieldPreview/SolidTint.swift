import CreatorKernel

/// A tint and the solid it was sampled on. The solid is held so that its identity (the key the scene looks it up by) can't be
/// taken over by another object while the tint is kept.
struct SolidTint {
    let solid: Solid
    let tint: FieldTint
}
