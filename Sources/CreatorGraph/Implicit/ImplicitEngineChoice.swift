/// Which engine evaluates implicit solids (implicit spec §4.1). The evaluator carries it to the Mesh node in `EvalContext`.
public enum ImplicitEngineChoice: String, Sendable, Hashable {
    /// The CPU engine, always. A context made by hand (the tests) has this.
    case cpu
    /// The GPU engine when the machine has one and the solid compiles, else the CPU (the CPU is a complete engine: Errata D11).
    case automatic
}
