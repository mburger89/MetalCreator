/// A sketch the solver refuses before solving, with a plain-language reason (spec §4).
struct SolveFailure: Error, Hashable, Sendable {
    var reason: String
}
