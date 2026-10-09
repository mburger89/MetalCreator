import CreatorGeometry
import CreatorSketch

/// The selection sorted by what it is, each group in ID order, for the constraint and dimension tools.
struct SelectionShape {
    var points: [SketchEntityID] = []
    var lines: [SketchEntityID] = []
    /// Arcs and circles.
    var rounds: [SketchEntityID] = []
    /// Projected edges.
    var projected: [SketchEntityID] = []

    init(_ selection: Set<SketchEntityID>, in sketch: Sketch) {
        for id in selection.sorted() {
            switch sketch.entities[id]?.kind {
            case .point?: points.append(id)
            case .line?: lines.append(id)
            case .arc?, .circle?: rounds.append(id)
            case .projected?: projected.append(id)
            case nil: break
            }
        }
    }

    var count: Int { points.count + lines.count + rounds.count + projected.count }

    /// Exactly `points` points, `lines` lines and `rounds` arcs or circles, and nothing else.
    func `is`(points: Int = 0, lines: Int = 0, rounds: Int = 0) -> Bool {
        self.points.count == points && self.lines.count == lines && self.rounds.count == rounds && projected.isEmpty
    }

    // The constraint `kind` makes from this selection, or `nil` when the selection doesn't fit it: one case per
    // constraint kind, each checking its own shape.
    // swiftlint:disable:next cyclomatic_complexity
    func constraint(_ kind: SketchConstraintKind, at position: (SketchEntityID) -> Vector2?) -> SketchConstraint? {
        switch kind {
        case .coincident: return `is`(points: 2) ? .coincident(points[0], points[1]) : nil
        case .pointOn:
            let curves = lines + rounds + projected
            return points.count == 1 && curves.count == 1 ? .pointOn(point: points[0], curve: curves[0]) : nil
        case .horizontal: return `is`(lines: 1) ? .horizontal(lines[0]) : `is`(points: 2) ? .horizontalPoints(points[0], points[1]) : nil
        case .vertical: return `is`(lines: 1) ? .vertical(lines[0]) : `is`(points: 2) ? .verticalPoints(points[0], points[1]) : nil
        case .parallel: return `is`(lines: 2) ? .parallel(lines[0], lines[1]) : nil
        case .perpendicular: return `is`(lines: 2) ? .perpendicular(lines[0], lines[1]) : nil
        case .tangent:
            if `is`(lines: 1, rounds: 1) { return .tangent(lines[0], rounds[0]) }
            return `is`(rounds: 2) ? .tangent(rounds[0], rounds[1]) : nil
        case .equal:
            if `is`(lines: 2) { return .equal(lines[0], lines[1]) }
            return `is`(rounds: 2) ? .equal(rounds[0], rounds[1]) : nil
        case .midpoint: return `is`(points: 1, lines: 1) ? .midpoint(point: points[0], line: lines[0]) : nil
        case .concentric: return `is`(rounds: 2) ? .concentric(rounds[0], rounds[1]) : nil
        case .symmetric: return `is`(points: 2, lines: 1) ? .symmetric(points[0], points[1], about: lines[0]) : nil
        case .fix:
            guard `is`(points: 1), let at = position(points[0]) else { return nil }
            return .fix(points[0], at: at)
        }
    }
}
