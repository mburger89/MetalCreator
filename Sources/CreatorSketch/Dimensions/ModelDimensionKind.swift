/// Chooses the dimension kind between two picked sketch entities, as the model dimension tool needs it.
public enum ModelDimensionKind {
    /// circle|arc + circle|arc|point → `.centreDistance`; lines within 0.5° of parallel on the solved positions (DIM-2's
    /// limit) → `.lineDistance`; other lines → `.angle`; point + line → `.distance(point, line)`; circle|arc + line →
    /// `.distance(its centre, line)`; point + point → `.distance`; the same entity, or anything else → nil.
    /// A projected entity counts as its `ProjectedCurve`'s kind (a circle has no centre point: with a line → nil).
    public static func between(_ a: SketchEntityID, _ b: SketchEntityID, in sketch: Sketch) -> DimensionKind? {
        guard a != b, let first = role(of: a, in: sketch), let second = role(of: b, in: sketch) else { return nil }
        switch (first, second) {
        case (.line, .line):
            return areParallel(a, b, in: sketch) ? .lineDistance(a, b) : .angle(a, b)
        case (.point, .point):
            return .distance(a, b)
        case (.point, .line):
            return .distance(a, b)
        case (.line, .point):
            return .distance(b, a)
        case (.round, .round), (.round, .point):
            return .centreDistance(a, b)
        case (.point, .round):
            return .centreDistance(a, b)
        case (.round(let centre?), .line):
            return .distance(centre, b)
        case (.line, .round(let centre?)):
            return .distance(centre, a)
        case (.round(nil), .line), (.line, .round(nil)):
            return nil
        }
    }

    /// What an entity is for choosing a kind. A round one carries its centre point, nil for a projected circle or arc.
    private enum Role {
        case point
        case line
        case round(centre: SketchEntityID?)
    }

    private static func role(of id: SketchEntityID, in sketch: Sketch) -> Role? {
        switch sketch.entities[id]?.kind {
        case .point?: .point
        case .line?: .line
        case .circle(let centre, _)?, .arc(let centre, _, _)?: .round(centre: centre)
        case .projected(let source)?:
            if case .line = source.curve { .line } else { .round(centre: nil) }
        case nil: nil
        }
    }

    /// Whether two lines are within half a degree of parallel (or antiparallel) on the solved positions.
    private static func areParallel(_ a: SketchEntityID, _ b: SketchEntityID, in sketch: Sketch) -> Bool {
        let position = { (point: SketchEntityID) in sketch.position(of: point) }
        guard let u = sketch.lineDirection(a, position: position), let v = sketch.lineDirection(b, position: position),
              u.length > 1e-9, v.length > 1e-9 else { return false }
        return abs(u.x * v.y - u.y * v.x) / (u.length * v.length) < parallelLimit
    }

    /// The sine of half a degree.
    private static let parallelLimit = 0.0087265354983
}
