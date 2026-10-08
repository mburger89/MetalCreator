extension Sketch {
    /// A plain-language name such as "Line 3": the kind, then the entity's 1-based position among
    /// entities of that kind in ID order. Construction geometry is counted with its kind.
    public func label(of id: SketchEntityID) -> String {
        guard let entity = entities[id] else { return "a deleted entity" }
        let kindName = Self.kindName(entity.kind)
        let sameKind = entityIDs.filter { other in entities[other].map { Self.kindName($0.kind) == kindName } ?? false }
        let ordinal = (sameKind.firstIndex(of: id) ?? 0) + 1
        return "\(kindName) \(ordinal)"
    }

    /// "Horizontal on Line 3", "Tangent on Line 1 and Arc 2", "Angle d4 (30°)".
    public func label(of ref: SketchConstraintRef) -> String {
        switch ref {
        case .constraint(let id):
            guard let constraint = constraints[id] else { return "a deleted constraint" }
            return label(of: constraint)
        case .dimension(let id):
            guard let dimension = dimensions[id] else { return "a deleted dimension" }
            return label(of: dimension)
        }
    }

    func label(of constraint: SketchConstraint) -> String {
        let names = constraint.entities.map { label(of: $0) }
        let title = switch constraint {
        case .coincident: "Coincident"
        case .pointOn: "Point on"
        case .horizontal, .horizontalPoints: "Horizontal"
        case .vertical, .verticalPoints: "Vertical"
        case .parallel: "Parallel"
        case .perpendicular: "Perpendicular"
        case .tangent: "Tangent"
        case .equal: "Equal"
        case .midpoint: "Midpoint"
        case .concentric: "Concentric"
        case .symmetric: "Symmetric"
        case .fix: "Fix"
        }
        if case .symmetric = constraint, names.count == 3 {
            return "\(title) on \(names[0]) and \(names[1]) about \(names[2])"
        }
        return "\(title) on \(Self.joined(names))"
    }

    /// "Angle d4 (30°)".
    func label(of dimension: SketchDimension) -> String {
        let unit = if case .angle = dimension.kind { "°" } else { " mm" }
        return "\(title(of: dimension)) (\(dimension.value.sketchDisplay)\(unit))"
    }

    /// "Angle d4": the kind and the name, without the value.
    func title(of dimension: SketchDimension) -> String {
        let kind = switch dimension.kind {
        case .distance: "Distance"
        case .length: "Length"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .angle: "Angle"
        }
        return "\(kind) \(dimension.name)"
    }

    /// "A conflicts with B." / "A conflicts with B and C." for a minimal conflict set.
    public func conflictMessage(_ refs: [SketchConstraintRef]) -> String {
        let names = refs.map { label(of: $0) }
        guard let first = names.first else { return "" }
        guard names.count > 1 else { return "\(first) can't be met." }
        return "\(first) conflicts with \(Self.joined(Array(names.dropFirst())))."
    }

    static func kindName(_ kind: SketchEntityKind) -> String {
        switch kind {
        case .point: "Point"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .projected: "Projected edge"
        }
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
