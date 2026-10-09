import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// A Dimension-tool click (sketcher spec §8: the kind follows from the picks). A circle gives a diameter and an
    /// arc a radius at once. A line waits: another line gives an angle, a point a distance, and a click on nothing its
    /// length. A point waits for a point or a line (a distance). The new dimension measures the geometry as it is, so
    /// nothing moves.
    func dimension(at p: Vector2, tolerance: Double) {
        let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance)
        guard let first = dimensionPick else {
            guard let picked else { return }
            switch sketch.entities[picked]?.kind {
            case .circle?: addMeasuredDimension(.diameter(picked))
            case .arc?: addMeasuredDimension(.radius(picked))
            case .line?, .point?: dimensionPick = picked
            default: refusal = "Pick a line, a point, an arc or a circle to dimension."
            }
            return
        }
        dimensionPick = nil
        guard let kind = dimensionKind(first, picked) else {
            refusal = "Those can't be dimensioned together. Pick two points, a point and a line, or two lines."
            return
        }
        addMeasuredDimension(kind)
    }

    /// The kind for a first pick and a second (nil: a click on nothing).
    private func dimensionKind(_ first: SketchEntityID, _ second: SketchEntityID?) -> DimensionKind? {
        let firstKind = sketch.entities[first]?.kind
        guard let second else {
            if case .line? = firstKind { return .length(first) }
            return nil
        }
        switch (firstKind, sketch.entities[second]?.kind) {
        case (.line?, .line?): return second == first ? .length(first) : .angle(first, second)
        case (.point?, .point?): return second == first ? nil : .distance(first, second)
        case (.point?, .line?), (.line?, .point?): return .distance(first, second)
        default: return nil
        }
    }

    /// Adds a driving dimension of `kind` at the value the geometry has now (measured as a reference first).
    private func addMeasuredDimension(_ kind: DimensionKind) {
        var edited = sketch
        let id = edited.addDimension(kind, value: 0, isDriving: false)
        guard let measured = SketchSolver.solve(edited).measurements[id], measured.isFinite else {
            refusal = "That can't be measured."
            return
        }
        edited.dimensions[id]?.value = measured
        edited.dimensions[id]?.isDriving = true
        commit(edited, "Dimension \(edited.dimensions[id]?.name ?? "")")
    }

    /// The inspector's dimensions, in ID order. A reference dimension shows what it measures now (its stored value is
    /// only the measurement from when it became a reference).
    public var dimensionRows: [DimensionRow] {
        let conflicts = conflictRefs
        return sketch.dimensionIDs.compactMap { id in
            guard let dimension = sketch.dimensions[id] else { return nil }
            let value = dimension.isDriving ? dimension.value : solution.measurements[id] ?? dimension.value
            return DimensionRow(id: id, kind: Self.kindName(dimension.kind), name: dimension.name,
                                value: DimensionText.format(value, kind: dimension.kind), isExposed: dimension.isExposed,
                                isDriving: dimension.isDriving, isWired: wiredDimensions.contains(id),
                                isConflicting: conflicts.contains(.dimension(id)))
        }
    }

    /// The inspector's constraints, in ID order.
    public var constraintRows: [ConstraintRow] {
        let conflicts = conflictRefs
        return sketch.constraintIDs.map { id in
            ConstraintRow(id: id, label: sketch.label(of: .constraint(id)), isConflicting: conflicts.contains(.constraint(id)))
        }
    }

    private var conflictRefs: Set<SketchConstraintRef> {
        if case .overConstrained(let conflicts) = solution.status { return Set(conflicts) }
        return []
    }

    static func kindName(_ kind: DimensionKind) -> String {
        switch kind {
        case .distance: "Distance"
        case .length: "Length"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .angle: "Angle"
        }
    }

    /// A typed value for a dimension: one step. Text that isn't a number is refused, and the field shows the old value.
    /// A wired dimension (its value comes from the wire) and a reference dimension (it only measures) are refused too.
    public func setValue(_ text: String, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id] else { return }
        if wiredDimensions.contains(id) {
            refusal = "Its value comes from the wire into “\(dimension.name)”."
            return
        }
        guard dimension.isDriving else {
            refusal = "\(dimension.name) is a reference: make it driving to set it."
            return
        }
        guard let value = DimensionText.parse(text) else {
            refusal = "“\(text)” isn't a number."
            return
        }
        if let problem = Self.valueProblem(value, kind: dimension.kind) {
            refusal = problem
            return
        }
        guard value != dimension.value else { return }
        var edited = sketch
        edited.dimensions[id]?.value = value
        commit(edited, "Change \(dimension.name)")
    }

    /// Why `value` can't drive a dimension of `kind` (sizes are more than 0 mm, angles 0 to 180°), or nil if it can.
    private static func valueProblem(_ value: Double, kind: DimensionKind) -> String? {
        switch kind {
        case .angle:
            return (0...180).contains(value) ? nil : "An angle must be between 0° and 180°."
        case .length, .distance, .radius, .diameter:
            return value > 0 ? nil : "A \(kindName(kind).lowercased()) must be more than 0 mm."
        }
    }

    /// Renames a dimension, refusing an empty or repeated name and one the Sketch node reserves (`isReservedName`).
    public func rename(_ id: DimensionID, to name: String) {
        guard let dimension = sketch.dimensions[id] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != dimension.name else { return }
        if isReservedName(trimmed) {
            refusal = "“\(trimmed)” is taken by the Sketch node's own inputs and settings. Pick another name."
            return
        }
        var edited = sketch
        guard edited.renameDimension(id, to: trimmed) else {
            refusal = trimmed.isEmpty ? "A dimension needs a name." : "Another dimension is already called “\(trimmed)”."
            return
        }
        commit(edited, "Rename \(dimension.name) to \(trimmed)")
    }

    /// "Expose as input" (sketcher spec §7): the dimension becomes an input socket named after it.
    public func setExposed(_ exposed: Bool, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id], dimension.isExposed != exposed else { return }
        var edited = sketch
        edited.dimensions[id]?.isExposed = exposed
        commit(edited, exposed ? "Expose \(dimension.name)" : "Stop Exposing \(dimension.name)")
    }

    /// Driving or reference (a reference dimension only measures, into the node's `measurements`). Either way it takes
    /// the value the geometry has now, so nothing moves.
    public func setDriving(_ driving: Bool, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id], dimension.isDriving != driving else { return }
        var edited = sketch
        edited.dimensions[id]?.isDriving = driving
        let measured = driving ? solution.measurements[id] : SketchSolver.solve(edited).measurements[id]
        if let measured, measured.isFinite { edited.dimensions[id]?.value = measured }
        commit(edited, driving ? "Make \(dimension.name) Driving" : "Make \(dimension.name) Reference")
    }

    /// Removes one constraint or dimension from the inspector's list. An exposed dimension is refused (its input and
    /// any wire into it would vanish: S1–S2 handoff).
    public func remove(_ ref: SketchConstraintRef) {
        var edited = sketch
        switch ref {
        case .constraint(let id):
            guard edited.constraints.removeValue(forKey: id) != nil else { return }
        case .dimension(let id):
            guard let dimension = edited.dimensions[id] else { return }
            guard !dimension.isExposed else {
                refusal = "That would remove \(dimension.name), which is exposed as an input. Stop exposing it first."
                return
            }
            edited.dimensions[id] = nil
        }
        commit(edited, "Delete \(sketch.label(of: ref))")
    }
}
