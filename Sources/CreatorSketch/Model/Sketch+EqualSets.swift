extension Sketch {
    /// The circles (or arcs) joined to `id` through `.equal` constraints, transitively, of the same entity kind as `id`, in ID order,
    /// `id` included; `[id]` when there are none; `[]` for an entity that is not a circle or arc.
    public func equalSet(of id: SketchEntityID) -> [SketchEntityID] {
        guard let isCircle = Self.curveFlavour(entities[id]?.kind) else { return [] }
        var parent: [SketchEntityID: SketchEntityID] = [:]
        func root(_ entity: SketchEntityID) -> SketchEntityID {
            var current = entity
            while let next = parent[current], next != current { current = next }
            return current
        }
        for constraintID in constraintIDs {
            guard case .equal(let a, let b) = constraints[constraintID],
                  Self.curveFlavour(entities[a]?.kind) == isCircle, Self.curveFlavour(entities[b]?.kind) == isCircle else { continue }
            let rootA = root(a), rootB = root(b)
            if rootA != rootB { parent[max(rootA, rootB)] = min(rootA, rootB) }
        }
        let target = root(id)
        return entityIDs.filter { entity in
            Self.curveFlavour(entities[entity]?.kind) == isCircle && root(entity) == target
        }
    }

    /// `true` for a circle, `false` for an arc, `nil` for anything else.
    private static func curveFlavour(_ kind: SketchEntityKind?) -> Bool? {
        switch kind {
        case .circle: true
        case .arc: false
        default: nil
        }
    }
}
