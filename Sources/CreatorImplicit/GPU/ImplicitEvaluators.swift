import CreatorGraph

/// Picks the engine that evaluates a solid (implicit spec §4.1): a GPU engine when asked for and available, else the CPU, which is a
/// complete engine on every platform (Errata D11). Names no GPU API: the engine comes from `ImplicitGPUEngines`.
public enum ImplicitEvaluators {
    /// The engine chosen, and whether it is a fall-back the person should hear about.
    public struct Selection: Sendable {
        public var evaluator: any ImplicitBatchEvaluator
        /// "Running on the CPU" when a GPU engine was wanted and the solid would not compile; `nil` otherwise, including on a machine
        /// with no GPU engine, where the CPU is all there is.
        public var warning: String?
        /// Why the GPU engine was not used, for the log, when it was wanted and the solid would not compile. Never shown to the person.
        public var diagnostic: String?
    }

    /// The warning's text.
    public static let cpuWarning = "Running on the CPU"

    /// The evaluator for `solid`. Compiling runs here, off the main actor when the caller is. `engine` is the machine's by default; the
    /// tests pass their own.
    public static func make(for solid: ImplicitSolid, choice: ImplicitEngineChoice,
                            engine: (any ImplicitGPUEngine)? = ImplicitGPUEngines.platformDefault) async -> Selection {
        let cpu = CPUBatchEvaluator(solid)
        guard choice == .automatic, let engine else { return Selection(evaluator: cpu, warning: nil, diagnostic: nil) }
        switch await engine.availability {
        case .available:
            break
        case .absent(let why):
            // No GPU for this engine: like a machine with no GPU engine, the CPU is all there is (plan xp-c, X-C4).
            return Selection(evaluator: cpu, warning: nil, diagnostic: "no GPU engine: \(why)")
        case .broken(let why):
            // A GPU engine that should run and cannot (its compiler library is missing, a pipeline was refused): the person is told.
            return Selection(evaluator: cpu, warning: cpuWarning, diagnostic: "the GPU engine cannot run: \(why)")
        }
        do {
            let program = try await engine.compile(solid)
            return Selection(evaluator: GPUBatchEvaluator(engine: engine, program: program), warning: nil, diagnostic: nil)
        } catch ImplicitCompileError.unsupported(let what) {
            // Not a bug: some parts have no GPU form yet. The CPU does it, and the person is told.
            return Selection(evaluator: cpu, warning: cpuWarning, diagnostic: "no GPU form: \(what)")
        } catch {
            return Selection(evaluator: cpu, warning: cpuWarning, diagnostic: "the GPU compiler failed: \(error)")
        }
    }
}
