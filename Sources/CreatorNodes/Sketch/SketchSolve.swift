import CreatorGeometry
import CreatorGraph
import CreatorSketch

/// What the Sketch node makes of a sketch whose wired values and projections are applied (sketcher
/// spec §7): solve, find regions, read reference dimensions, and map the solver's status to node states.
enum SketchSolve {
    struct Output {
        /// The regions as profiles on the sketch plane, largest first (spec §5 step 5).
        var profiles: [Profile2D]
        /// Reference (non-driving) dimensions' measured values, in name order.
        var measurements: [Double]
        var warnings: [String]
    }

    static let nothingDrawn = "Draw a closed shape in the sketch to make a profile."

    /// Over-constrained and failed solves throw their plain-language messages, so the evaluator shows an
    /// error and the viewport keeps the last good result as a ghost (parent spec §4.4).
    static func run(_ sketch: Sketch, on plane: Plane) throws -> Output {
        let solution = SketchSolver.solve(sketch)
        switch solution.status {
        case .overConstrained:
            let messages = solution.conflictMessages.filter { !$0.isEmpty }
            throw NodeError.invalidValue(messages.isEmpty ? "The sketch's constraints conflict." : messages.joined(separator: "\n"))
        case .failed(let reason):
            throw NodeError.invalidValue(reason)
        case .solved, .underConstrained:
            break
        }
        var warnings: [String] = []
        let freedom = solution.degreesOfFreedom
        if freedom > 0 {
            let count = freedom == 1 ? "1 degree" : "\(freedom.display) degrees"
            warnings.append("The sketch has \(count) of freedom left, so it isn't fully constrained.")
        }
        var solved = sketch
        solved.remember(solution)
        let found = SketchRegions.find(in: solved)
        if let open = found.warning { warnings.append(open) }
        if found.regions.isEmpty, found.openCurves.isEmpty { warnings.append(nothingDrawn) }
        let measured = measurements(sketch, solution)
        return Output(profiles: found.regions.map { $0.profile(on: plane) }, measurements: measured.values,
                      warnings: warnings + measured.warnings)
    }

    /// Why a reference dimension isn't measured, for `unmeasured(_:because:)`.
    static let onSuspendedEdge = "its projected edge is suspended"
    static let wrongGeometry = "it doesn't fit the curve it is on"

    static func unmeasured(_ name: String, because reason: String) -> String {
        "Reference dimension “\(name)” can't be measured: \(reason). “measurements” is empty until it can be."
    }

    /// The reference dimensions' values in name order. A position in the list is a dimension, so when one
    /// can't be measured (on a suspended projection, whose stored curve S4 never refreshes, or on geometry
    /// it doesn't fit) the list is empty rather than shifted, and a warning names each such dimension.
    private static func measurements(_ sketch: Sketch, _ solution: SketchSolution) -> (values: [Double], warnings: [String]) {
        let references = sketch.dimensionIDs.compactMap { id in sketch.dimensions[id].map { (id, $0) } }
            .filter { !$0.1.isDriving }
            .sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }
        var values: [Double] = []
        var warnings: [String] = []
        for (id, dimension) in references {
            let onSuspended = dimension.kind.entities.contains { entity in
                if case .projected(let source)? = sketch.entities[entity]?.kind { return source.isSuspended }
                return false
            }
            if onSuspended {
                warnings.append(unmeasured(dimension.name, because: onSuspendedEdge))
            } else if let value = solution.measurements[id] {
                values.append(value)
            } else {
                warnings.append(unmeasured(dimension.name, because: wrongGeometry))
            }
        }
        return (warnings.isEmpty ? values : [], warnings)
    }
}
