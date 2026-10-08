extension SketchSolver {
    /// True when adding `constraint` to `sketch` would add no new condition at the warm start:
    /// its Jacobian rows lie in the span of the rows already in the component it joins, so the
    /// sketch already holds it and adding it would only be reported as redundant (spec §4). A
    /// constraint that touches a suspended projected edge, or a sketch that can't be built into
    /// equations, is never implied.
    static func isImplied(_ constraint: SketchConstraint, in sketch: Sketch) -> Bool {
        var trial = sketch
        let ref = SketchConstraintRef.constraint(trial.add(constraint))
        let layout = UnknownLayout(trial)
        let x0 = layout.warmStart(trial)
        guard let built = try? TermBuilder(sketch: trial, layout: layout, x0: x0).build(),
              !built.suspended.contains(ref) else { return false }
        let partition = ComponentPartition(terms: built.terms, layout: layout)
        // A trivially met constraint builds no rows, so it joins no component.
        guard let component = partition.components.first(where: { $0.terms.contains { $0.userRef == ref } }) else {
            return true
        }
        let system = ComponentSystem(terms: component.terms, columns: component.columns, base: x0)
        let (_, jacobian) = system.evaluate(system.local(x0))
        let others = ComponentSolver.rows(of: system) { $0.userRef != ref }
        return RankRevealingQR(jacobian.selectingRows(others)).rank == RankRevealingQR(jacobian).rank
    }
}
