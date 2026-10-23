/// Whether a GPU engine can run here (plan xp-c, X-C4), asked by `ImplicitEvaluators.make` before it compiles.
public enum ImplicitEngineAvailability: Sendable, Equatable {
    case available
    /// No GPU for it: the CPU runs and nobody is told, as on a machine with no GPU engine.
    case absent(String)
    /// It should run and cannot (the compiler library is missing, a pipeline was refused): the CPU runs and the person is told, with the reason.
    case broken(String)
}
