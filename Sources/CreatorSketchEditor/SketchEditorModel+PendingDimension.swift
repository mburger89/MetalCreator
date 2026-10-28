import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    static let notMeasurable = "That can't be measured."
    static let samePlace = "Those are in the same place: there is nothing to dimension."

    /// Starts the pending dimension of `aligned`, measured on the sketch as it is. `.picked` (a circle's or arc's own size) waits
    /// for a second click; any other phase opens the value box, or goes straight to placing for a reference.
    func beginPending(_ aligned: DimensionKind, at p: Vector2, phase: PendingDimension.Phase) {
        guard let measured = sketch.measuredDimension(aligned) else {
            refusal = unmeasurableReason(aligned)
            return
        }
        var next = PendingDimension(aligned: aligned, kind: aligned, value: measured.value, isDriving: measured.isDriving,
                                    labelPoint: p, phase: phase, isOrientationLocked: false)
        orient(&next, at: p)
        pending = next
        if phase != .picked { enterPending() }
    }

    /// Opens the value box on the pending dimension, or, for a reference (nothing to type), goes on to placing.
    func enterPending() {
        guard var current = pending else { return }
        current.phase = current.isDriving ? .entering : .placing
        pending = current
        if current.isDriving { events.openValueBox(SketchDimensionDrawing.pendingID) }
    }

    /// A Dimension-tool click while a dimension is pending.
    func pendingClick(_ current: PendingDimension, at p: Vector2, tolerance: Double) {
        switch current.phase {
        case .picked: radialClick(current, at: p, tolerance: tolerance)
        case .entering: break
        case .placing: placePending(at: p)
        }
    }

    /// The second click after a circle or arc: on nothing or the same one it keeps the diameter or radius; on another circle,
    /// arc or point it is the distance between centres, on a line the distance from the centre to the line.
    private func radialClick(_ current: PendingDimension, at p: Vector2, tolerance: Double) {
        guard let round = current.aligned.entities.first,
              let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance),
              picked != round else {
            pending?.labelPoint = p
            enterPending()
            return
        }
        pending = nil
        switch sketch.entities[picked]?.kind {
        case .circle?, .arc?, .point?:
            beginPending(.centreDistance(round, picked), at: p, phase: .entering)
        case .projected(let source)?:
            guard source.curve.isRound else { return refusal = Self.notMeasurable }
            beginPending(.centreDistance(round, picked), at: p, phase: .entering)
        case .line?:
            guard let centre = centrePoint(of: round) else { return refusal = Self.notMeasurable }
            beginPending(.distance(centre, picked), at: p, phase: .entering)
        case nil:
            refusal = Self.notMeasurable
        }
    }

    /// The pointer moved: the label follows it, and, until a value is typed, so does the orientation.
    func movePending(to p: Vector2) {
        guard var current = pending, current.phase != .entering else { return }
        current.labelPoint = p
        orient(&current, at: p)
        pending = current
    }

    /// The placing click: the dimension is committed as one "Add Dimension" step, and, after a typed value, the host checks what
    /// that did downstream.
    private func placePending(at p: Vector2) {
        guard var current = pending else { return }
        current.labelPoint = p
        orient(&current, at: p)
        var edited = pendingOrigin?.sketch ?? sketch
        let id = edited.addDimension(current.kind, value: current.value, isDriving: current.isDriving)
        edited.dimensions[id]?.labelPoint = current.labelPoint
        pending = nil
        pendingOrigin = nil
        commit(edited, "Dimension \(edited.dimensions[id]?.name ?? "")", named: SketchStepName.addDimension)
        guard current.isOrientationLocked else { return }
        commitCheck = Task {
            if let message = await events.checkValueCommit() { refusal = message }
        }
    }

    /// Drops the pending dimension and puts back the geometry a typed value moved.
    func dropPending() {
        if let origin = pendingOrigin {
            sketch = origin.sketch
            solution = origin.solution
        }
        pending = nil
        pendingOrigin = nil
    }

    /// What a typed value comes to for the pending dimension (`commitValue`): checked as the inspector checks it, solved on the
    /// sketch as it was, and refused when it can't be solved or flips a corner. The geometry then shows it, uncommitted.
    func commitPendingValue(_ text: String) -> DimensionCommitOutcome {
        guard let current = pending, current.phase != .picked else { return .refused("That dimension is gone.") }
        switch typedValue(text, kind: current.kind, current: current.value) {
        case .refused(let message):
            return .refused(message)
        case .unchanged:
            pending?.phase = .placing
            return .accepted
        case .value(let value):
            let base = pendingOrigin ?? (sketch, solution)
            var edited = base.sketch
            edited.addDimension(current.kind, value: value, isDriving: true)
            let solved = SketchSolver.solve(edited)
            switch solved.status {
            case .overConstrained: return .refused("That value would over-constrain the sketch.")
            case .failed(let reason): return .refused(reason)
            case .solved, .underConstrained: break
            }
            guard !flipCheck(base.solution, solved, edited) else { return .refused(SketchFlipCheck.refusal) }
            pendingOrigin = base
            solution = solved
            sketch = Self.remembering(base.sketch, solved)
            pending = PendingDimension(aligned: current.aligned, kind: current.kind, value: value, isDriving: true,
                                       labelPoint: current.labelPoint, phase: .placing, isOrientationLocked: true)
            return .accepted
        }
    }

    /// The pending dimension's box ended: Return untouched goes on to placing; Esc or focus lost drops the whole dimension.
    public func valueBoxClosed(_ id: OverlayDimensionID, by ending: DimensionValueBoxEnding) {
        guard id == SketchDimensionDrawing.pendingID, pending != nil else { return }
        switch ending {
        case .committed: break
        case .unchanged: if pending?.phase == .entering { pending?.phase = .placing }
        case .cancelled: dropPending()
        }
    }

    // MARK: Right-click while placing

    static let overDefining = "That would over-define the sketch."

    /// The entries of the right-click menu while the pending dimension is being placed (spec §4.2): Radius or Diameter for a
    /// round one, Driving or Reference for any. Nothing otherwise.
    public func menuActions(at point: ScreenPoint) -> [HostMenuAction] {
        guard let current = pending, current.phase == .placing else { return [] }
        var actions: [HostMenuAction] = []
        switch current.kind {
        case .radius: actions.append(HostMenuAction(title: "Diameter", key: "dimension.diameter"))
        case .diameter: actions.append(HostMenuAction(title: "Radius", key: "dimension.radius"))
        default: break
        }
        actions.append(current.isDriving ? HostMenuAction(title: "Reference", key: "dimension.reference")
                                         : HostMenuAction(title: "Driving", key: "dimension.driving"))
        return actions
    }

    /// Runs an entry of `menuActions(at:)` on the pending dimension. Radius and diameter convert the value and keep the lock;
    /// Driving is refused when the sketch could not take it.
    public func performMenuAction(_ action: HostMenuAction) {
        guard var current = pending, current.phase == .placing else { return }
        switch action.key {
        case "dimension.diameter", "dimension.radius":
            guard let converted = Self.convertedRound(current, toDiameter: action.key == "dimension.diameter") else { return }
            current = converted
        case "dimension.reference":
            guard current.isDriving else { return }
            makeReference(&current)
        case "dimension.driving":
            guard !current.isDriving else { return }
            guard let measured = sketch.measuredDimension(current.kind), measured.isDriving else {
                refusal = Self.overDefining
                return
            }
            current.isDriving = true
        default:
            return
        }
        pending = current
    }

    /// `current` as a diameter (value ×2) or a radius (value ÷2); `nil` when it is not the other one.
    private static func convertedRound(_ current: PendingDimension, toDiameter: Bool) -> PendingDimension? {
        var next = current
        switch (current.kind, toDiameter) {
        case (.radius(let id), true):
            next.kind = .diameter(id)
            next.value *= 2
        case (.diameter(let id), false):
            next.kind = .radius(id)
            next.value /= 2
        default:
            return nil
        }
        next.aligned = next.kind
        return next
    }

    /// Makes `current` a reference. A typed value moved the geometry; a reference measures the geometry as it was.
    private func makeReference(_ current: inout PendingDimension) {
        if let origin = pendingOrigin {
            sketch = origin.sketch
            solution = origin.solution
            pendingOrigin = nil
            if let measured = sketch.measuredDimension(current.kind) { current.value = measured.value }
        }
        current.isDriving = false
    }

    /// Re-chooses the kind from where the label is, and measures it, unless a typed value locked it.
    private func orient(_ current: inout PendingDimension, at label: Vector2) {
        guard !current.isOrientationLocked, let (a, b) = linearEnds(of: current.aligned) else { return }
        let kind = LinearOrientation.chosen(from: a, to: b, label: label).kind(of: current.aligned)
        guard kind != current.kind, let measured = sketch.measuredDimension(kind) else { return }
        current.kind = kind
        current.value = measured.value
        current.isDriving = measured.isDriving
    }

    /// The two ends of a distance between points or centres (the kinds that take an orientation).
    private func linearEnds(of kind: DimensionKind) -> (Vector2, Vector2)? {
        switch kind {
        case .distance(let a, let b):
            guard case .point? = sketch.entities[a]?.kind, case .point? = sketch.entities[b]?.kind else { return nil }
        case .centreDistance:
            break
        default:
            return nil
        }
        let ids = kind.entities
        guard let a = SketchDimensionDrawing.centre(SketchDimensionDrawing.shape(of: ids[0], sketch: sketch, solution: solution)),
              let b = SketchDimensionDrawing.centre(SketchDimensionDrawing.shape(of: ids[1], sketch: sketch, solution: solution))
        else { return nil }
        return (a, b)
    }

    /// Why `kind` couldn't be measured: the geometry is in one place (a distance of nothing), or it just can't be.
    private func unmeasurableReason(_ kind: DimensionKind) -> String {
        switch kind {
        case .length, .distance, .centreDistance, .lineDistance, .horizontalDistance, .verticalDistance:
            var probe = sketch
            let id = probe.addDimension(kind, value: 0, isDriving: false)
            if let measured = SketchSolver.solve(probe).measurements[id], measured.isFinite, measured < 1e-9 { return Self.samePlace }
        case .radius, .diameter, .angle:
            break
        }
        return Self.notMeasurable
    }

    /// The centre point of a circle or arc; `nil` for another entity, and for a projected circle (it has no point).
    func centrePoint(of id: SketchEntityID) -> SketchEntityID? {
        switch sketch.entities[id]?.kind {
        case .circle(let center, _)?, .arc(let center, _, _)?: center
        default: nil
        }
    }

    /// Whether `id` is a circle or an arc, drawn or projected.
    func isRound(_ id: SketchEntityID) -> Bool {
        switch sketch.entities[id]?.kind {
        case .circle?, .arc?: true
        case .projected(let source)?: source.curve.isRound
        default: false
        }
    }
}

extension ProjectedCurve {
    /// A circle or an arc.
    var isRound: Bool {
        if case .line = self { false } else { true }
    }
}
