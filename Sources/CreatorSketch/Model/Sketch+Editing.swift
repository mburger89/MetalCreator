import CreatorGeometry
import Foundation

extension Sketch {
    /// Reserves the next raw ID value.
    mutating func takeNextID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Adds an entity and returns its ID.
    @discardableResult
    public mutating func add(_ entity: SketchEntity) -> SketchEntityID {
        let id = SketchEntityID(takeNextID())
        entities[id] = entity
        return id
    }

    @discardableResult
    public mutating func addPoint(_ position: Vector2, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.point(position), isConstruction: isConstruction))
    }

    /// Adds a line between two existing points.
    @discardableResult
    public mutating func addLine(from start: SketchEntityID, to end: SketchEntityID, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.line(start: start, end: end), isConstruction: isConstruction))
    }

    /// Adds two new points and the line between them.
    @discardableResult
    public mutating func addLine(_ start: Vector2, _ end: Vector2, isConstruction: Bool = false) -> SketchEntityID {
        let a = addPoint(start)
        let b = addPoint(end)
        return addLine(from: a, to: b, isConstruction: isConstruction)
    }

    /// Adds a counter-clockwise arc through existing points.
    @discardableResult
    public mutating func addArc(center: SketchEntityID, start: SketchEntityID, end: SketchEntityID,
                                isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.arc(center: center, start: start, end: end), isConstruction: isConstruction))
    }

    /// Adds a circle around an existing centre point.
    @discardableResult
    public mutating func addCircle(center: SketchEntityID, radius: Double, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.circle(center: center, radius: radius), isConstruction: isConstruction))
    }

    /// Adds a centre point and a circle around it.
    @discardableResult
    public mutating func addCircle(center: Vector2, radius: Double, isConstruction: Bool = false) -> SketchEntityID {
        addCircle(center: addPoint(center), radius: radius, isConstruction: isConstruction)
    }

    @discardableResult
    public mutating func add(_ constraint: SketchConstraint) -> SketchConstraintID {
        let id = SketchConstraintID(takeNextID())
        constraints[id] = constraint
        return id
    }

    /// Adds a dimension named with the first free `d1`, `d2`, … name.
    @discardableResult
    public mutating func addDimension(_ kind: DimensionKind, value: Double, isDriving: Bool = true) -> DimensionID {
        let id = DimensionID(takeNextID())
        dimensions[id] = SketchDimension(kind: kind, name: nextDimensionName(), value: value, isDriving: isDriving)
        return id
    }

    /// The first name `dN` (N = 1, 2, …) that no dimension uses.
    public func nextDimensionName() -> String {
        let used = Set(dimensions.values.map(\.name))
        var number = 1
        while used.contains("d\(number)") { number += 1 }
        return "d\(number)"
    }

    /// Renames a dimension. Returns false, changing nothing, when `name` is empty after trimming
    /// spaces or another dimension already uses it.
    @discardableResult
    public mutating func renameDimension(_ id: DimensionID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, dimensions[id] != nil,
              !dimensions.contains(where: { $0.key != id && $0.value.name == trimmed }) else { return false }
        dimensions[id]?.name = trimmed
        return true
    }

    /// Removes an entity, every entity built on it (a line loses a point → the line goes), and
    /// every constraint, dimension and warm-start value that refers to anything removed.
    public mutating func removeEntity(_ id: SketchEntityID) {
        var doomed: Set<SketchEntityID> = [id]
        var changed = true
        while changed {
            changed = false
            for (other, entity) in entities where !doomed.contains(other) && !doomed.isDisjoint(with: entity.kind.referencedPoints) {
                doomed.insert(other)
                changed = true
            }
        }
        for entity in doomed {
            entities[entity] = nil
            solved[entity] = nil
        }
        constraints = constraints.filter { doomed.isDisjoint(with: $0.value.entities) }
        dimensions = dimensions.filter { doomed.isDisjoint(with: $0.value.kind.entities) }
    }

    /// Removes point entities that no curve uses and no constraint or dimension mentions.
    public mutating func removeOrphanPoints(_ candidates: [SketchEntityID]) {
        for point in candidates where isOrphan(point) {
            removeEntity(point)
        }
    }

    func isOrphan(_ point: SketchEntityID) -> Bool {
        guard case .point = entities[point]?.kind else { return false }
        if entities.values.contains(where: { $0.kind.referencedPoints.contains(point) }) { return false }
        if constraints.values.contains(where: { $0.entities.contains(point) }) { return false }
        return !dimensions.values.contains(where: { $0.kind.entities.contains(point) })
    }

    /// The point's current position: the last solve's value, or the drawn one.
    public func position(of point: SketchEntityID) -> Vector2? {
        if case .point(let solvedPosition) = solved[point] { return solvedPosition }
        if case .point(let drawn) = entities[point]?.kind { return drawn }
        return nil
    }

    /// The circle's current radius: the last solve's value, or the drawn one.
    public func radius(of circle: SketchEntityID) -> Double? {
        if case .radius(let solvedRadius) = solved[circle] { return solvedRadius }
        if case .circle(_, let drawn) = entities[circle]?.kind { return drawn }
        return nil
    }

    /// Moves a point: sets its drawn position and its warm start.
    public mutating func move(_ point: SketchEntityID, to position: Vector2) {
        guard case .point = entities[point]?.kind else { return }
        entities[point]?.kind = .point(position)
        solved[point] = .point(position)
    }

    /// Every constraint and driving or reference dimension, constraints first, each by ID.
    public var constraintRefs: [SketchConstraintRef] {
        constraintIDs.map(SketchConstraintRef.constraint) + dimensionIDs.map(SketchConstraintRef.dimension)
    }
}
