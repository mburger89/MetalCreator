extension TermBuilder {
    /// Adds a term for each constraint, skipping (and recording) those that touch a suspended projected edge or
    /// one whose kind no longer fits them.
    func addConstraintTerms(to output: inout Output) throws(SolveFailure) {
        for id in sketch.constraintIDs {
            guard let constraint = sketch.constraints[id] else { continue }
            let ref = SketchConstraintRef.constraint(id)
            try requireExisting(constraint.entities, ref)
            if touchesSuspended(constraint.entities) {
                output.suspended.append(ref)
                continue
            }
            let equations: [Equation]
            do {
                equations = try self.equations(for: constraint, ref)
            } catch where error.blamesProjection {
                output.suspended.append(ref)
                continue
            }
            for equation in equations where !isTriviallyMet(equation) {
                output.terms.append(SolverTerm(role: .user(ref), equation: equation))
            }
        }
    }

    /// The same for each driving dimension.
    func addDimensionTerms(to output: inout Output) throws(SolveFailure) {
        for id in sketch.dimensionIDs {
            guard let dimension = sketch.dimensions[id], dimension.isDriving else { continue }
            let ref = SketchConstraintRef.dimension(id)
            try requireExisting(dimension.kind.entities, ref)
            if touchesSuspended(dimension.kind.entities) {
                output.suspended.append(ref)
                continue
            }
            try validate(dimension)
            let equation: Equation
            do {
                equation = try self.equation(for: dimension, ref)
            } catch where error.blamesProjection {
                output.suspended.append(ref)
                continue
            }
            if !isTriviallyMet(equation) { output.terms.append(SolverTerm(role: .user(ref), equation: equation)) }
        }
    }
}
