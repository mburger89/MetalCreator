/// A sketch the solver refuses before solving, with a plain-language reason (spec §4).
struct SolveFailure: Error, Hashable, Sendable {
    var reason: String
    /// The refusal is a wrong-kind operand that is, or pairs with, a projected edge. Such an edge's kind follows the model
    /// upstream, so the constraint is suspended rather than the sketch failed (sketcher spec §7).
    var blamesProjection = false
}
