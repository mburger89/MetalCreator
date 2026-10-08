/// Minimal conflict sets for one component (spec §4): sets of user constraints and dimensions
/// that can't all hold, or whose rows are linearly dependent. Each set is minimal (every member
/// is needed), and a component with several independent conflicts reports one set per conflict,
/// so removing every reported set leaves the component consistent and independent.
enum ConflictSearch {
    /// The most conflict sets reported for one component. Past this, the sets found are reported
    /// and the rest show up once those are fixed.
    static let setLimit = 8
    /// A row takes part in a stalled least-squares fit when its residual is at least this
    /// fraction of the largest one there.
    static let involvedFraction = 1e-3

    struct Result: Sendable {
        /// Minimal sets, each in term order (constraints by ID, then dimensions by ID), and the
        /// sets in that same order by their members.
        var sets: [[SketchConstraintRef]]
        /// How many trial solves the search ran. Tests use it to pin the narrowing.
        var trialSolves: Int
    }

    /// Conflicts of a component that can't be satisfied. `stalled` is where its solve stopped.
    ///
    /// Each round narrows before filtering: the refs whose rows still carry residual at the
    /// stalled least-squares point are where the misfit sits. If those alone can't be met
    /// (one trial solve), the deletion filter runs on them only; otherwise on everything left.
    /// Either way the filter's result is a minimal unsatisfiable set, because the filter only
    /// ever drops a member while what remains still can't be met.
    static func unsatisfiableSets(_ system: ComponentSystem, from start: [Double], stalled: [Double]) -> Result {
        var trials = 0
        func trial(_ refs: Set<SketchConstraintRef>) -> LevenbergMarquardt.Outcome {
            trials += 1
            return solveRestricted(system, to: refs, from: start)
        }
        var sets: [[SketchConstraintRef]] = []
        var remaining = ComponentSolver.refs(of: system)
        var stalledAt = stalled
        while sets.count < setLimit {
            let candidates = involved(system, refs: Set(remaining), at: stalledAt)
            var pool = remaining
            if candidates.count < remaining.count,
               trial(Set(candidates)).maxResidual > ComponentSolver.satisfiedTolerance {
                pool = candidates
            }
            var kept = pool
            for ref in pool {
                let without = Set(kept.filter { $0 != ref })
                if trial(without).maxResidual > ComponentSolver.satisfiedTolerance {
                    kept.removeAll { $0 == ref }
                }
            }
            guard !kept.isEmpty else { break }
            sets.append(kept)
            remaining.removeAll { kept.contains($0) }
            let rest = trial(Set(remaining))
            if rest.maxResidual <= ComponentSolver.satisfiedTolerance {
                // What is left can be met; it may still repeat itself.
                let dependent = dependentSets(system.filtered { term in term.userRef.map(remaining.contains) ?? true },
                                              at: rest.x, limit: setLimit - sets.count)
                sets += dependent
                break
            }
            stalledAt = rest.x
        }
        return Result(sets: ordered(sets), trialSolves: trials)
    }

    /// Conflicts of a satisfied component whose user rows are linearly dependent at `x`: a
    /// deletion filter on rank finds one minimal dependent set, which is set aside before
    /// looking for the next while the rest is still dependent.
    static func dependentSets(_ system: ComponentSystem, at x: [Double], limit: Int = setLimit) -> [[SketchConstraintRef]] {
        let (_, jacobian) = system.evaluate(x)
        func isDependent(_ refs: Set<SketchConstraintRef>) -> Bool {
            let rowIndices = ComponentSolver.rows(of: system) { term in term.userRef.map(refs.contains) ?? false }
            return RankRevealingQR(jacobian.selectingRows(rowIndices)).rank < rowIndices.count
        }
        var sets: [[SketchConstraintRef]] = []
        var remaining = ComponentSolver.refs(of: system)
        while sets.count < limit, isDependent(Set(remaining)) {
            var kept = remaining
            for ref in remaining {
                let without = Set(kept.filter { $0 != ref })
                if isDependent(without) { kept.removeAll { $0 == ref } }
            }
            guard !kept.isEmpty else { break }
            sets.append(kept)
            remaining.removeAll { kept.contains($0) }
        }
        return ordered(sets)
    }

    /// Sets in reading order: by their members, constraints before dimensions, each in ID order.
    static func ordered(_ sets: [[SketchConstraintRef]]) -> [[SketchConstraintRef]] {
        sets.sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// The refs (in term order) with a row whose residual at `x` is a real part of the misfit.
    static func involved(_ system: ComponentSystem, refs: Set<SketchConstraintRef>, at x: [Double]) -> [SketchConstraintRef] {
        let residuals = system.residuals(x)
        let largest = LevenbergMarquardt.maxAbs(residuals)
        var seen = Set<SketchConstraintRef>()
        var result: [SketchConstraintRef] = []
        for (term, range) in zip(system.terms, system.rowRanges) {
            guard let ref = term.userRef, refs.contains(ref), !seen.contains(ref) else { continue }
            if range.contains(where: { abs(residuals[$0]) >= involvedFraction * largest }) {
                seen.insert(ref)
                result.append(ref)
            }
        }
        return result
    }

    /// Solves only `refs` (plus the implicit rows they reach) from `start`, varying only the
    /// columns those terms touch, so a small trial set is a small solve. The returned `x` is
    /// local to `system`, with every other column left at `start`.
    static func solveRestricted(_ system: ComponentSystem, to refs: Set<SketchConstraintRef>,
                                from start: [Double]) -> LevenbergMarquardt.Outcome {
        var terms = system.terms.filter { term in term.userRef.map(refs.contains) ?? false }
        var columns = Set(terms.flatMap(\.equation.columns))
        var implicit = system.terms.filter { $0.userRef == nil }
        while true {
            let reached = implicit.filter { $0.equation.columns.contains(where: columns.contains) }
            guard !reached.isEmpty else { break }
            terms += reached
            columns.formUnion(reached.flatMap(\.equation.columns))
            implicit.removeAll { reached.contains($0) }
        }
        let globalStart = system.global(start)
        let restricted = ComponentSystem(terms: terms, columns: columns.sorted(), base: globalStart)
        let outcome = LevenbergMarquardt.minimize(restricted, from: restricted.local(globalStart))
        return LevenbergMarquardt.Outcome(x: system.local(restricted.global(outcome.x)),
                                          maxResidual: outcome.maxResidual, iterations: outcome.iterations)
    }
}
