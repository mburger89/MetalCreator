import CreatorGeometry

/// The numeric constraint solver (spec §4): decomposition into connected components, warm start
/// from `Sketch.solved`, Levenberg–Marquardt with dense QR, drag mode, rank-revealing DOF and
/// freedom analysis, and minimal conflict sets. Pure and deterministic.
public enum SketchSolver {
    /// Solves `sketch`. `dragging` maps point entities to where the pointer wants them; those
    /// points become soft targets and everything else slides along its remaining freedom.
    public static func solve(_ sketch: Sketch, dragging: [SketchEntityID: Vector2] = [:]) -> SketchSolution {
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let built: TermBuilder.Output
        do {
            built = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build()
        } catch {
            return failed(sketch, layout: layout, x: x0, reason: error.reason)
        }
        let drags = dragging.keys.sorted().compactMap { id -> SolverTerm? in
            guard let column = layout.pointColumns[id], let target = dragging[id], target.isFinite else { return nil }
            return SolverTerm(role: .drag, equation: .target(.unknown(column: column), target))
        }
        let partition = ComponentPartition(terms: built.terms + drags, layout: layout)
        var x = x0
        var conflictSets: [[SketchConstraintRef]] = []
        var freeColumns = Set<Int>()
        var dof = 0
        for component in partition.components {
            let outcome = ComponentSolver.solve(component, base: x0)
            for (local, column) in component.columns.enumerated() { x[column] = outcome.x[local] }
            conflictSets += outcome.conflictSets
            freeColumns.formUnion(outcome.freeColumns)
            dof += outcome.degreesOfFreedom
        }
        let conflicts = conflictSets.flatMap { $0 }
        let status: SketchSolveStatus = if !conflicts.isEmpty {
            .overConstrained(conflicts: conflicts)
        } else if dof > 0 {
            .underConstrained(dof: dof)
        } else {
            .solved
        }
        var solution = assemble(sketch, layout: layout, x: x, status: status, freeColumns: freeColumns, conflicts: conflicts)
        solution.conflictMessages = conflictSets.map { sketch.conflictMessage($0) }
        solution.suspended = built.suspended
        return solution
    }

    static func failed(_ sketch: Sketch, layout: UnknownLayout, x: [Double], reason: String) -> SketchSolution {
        assemble(sketch, layout: layout, x: x, status: .failed(reason: reason), freeColumns: [], conflicts: [])
    }

    static func assemble(_ sketch: Sketch, layout: UnknownLayout, x: [Double], status: SketchSolveStatus,
                         freeColumns: Set<Int>, conflicts: [SketchConstraintRef]) -> SketchSolution {
        var points: [SketchEntityID: Vector2] = [:]
        for (id, column) in layout.pointColumns { points[id] = Vector2(x[column], x[column + 1]) }
        var radii: [SketchEntityID: Double] = [:]
        for (id, column) in layout.radiusColumns { radii[id] = x[column] }
        var conflicting = Set<SketchEntityID>()
        for ref in conflicts {
            switch ref {
            case .constraint(let id): conflicting.formUnion(sketch.constraints[id]?.entities ?? [])
            case .dimension(let id): conflicting.formUnion(sketch.dimensions[id]?.kind.entities ?? [])
            }
        }
        func isFree(_ id: SketchEntityID) -> Bool {
            if let column = layout.pointColumns[id] { return freeColumns.contains(column) || freeColumns.contains(column + 1) }
            return false
        }
        var freedom: [SketchEntityID: EntityFreedom] = [:]
        for (id, entity) in sketch.entities {
            let moves: Bool = switch entity.kind {
            case .point: isFree(id)
            case .line(let start, let end): isFree(start) || isFree(end)
            case .arc(let center, let start, let end): isFree(center) || isFree(start) || isFree(end)
            case .circle(let center, _): isFree(center) || layout.radiusColumns[id].map(freeColumns.contains) == true
            case .projected: false
            }
            freedom[id] = conflicting.contains(id) ? .conflicting : moves ? .free : .fixed
        }
        let measurements = SketchMeasure.referenceValues(sketch, points: points, radii: radii)
        return SketchSolution(status: status, points: points, radii: radii, freedom: freedom, conflictMessages: [],
                              suspended: [], measurements: measurements)
    }
}
