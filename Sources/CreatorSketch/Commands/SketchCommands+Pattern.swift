import CreatorGeometry
import Foundation

extension SketchCommands {
    /// The most instances one pattern command makes. The solver is dense (O(n³) in the unknowns)
    /// and re-solves every drag frame, so a pattern can't be allowed to grow a sketch past what
    /// it solves interactively; 100 copies of a small feature stay in that range.
    static let patternLimit = 100

    /// `count − 1` copies of the selection, each `spacing` further along `direction` (spec §3).
    ///
    /// Every instance is held as an exact translation, with exactly two rows per copied point, so
    /// patterning never adds redundancy or freedom. A construction connector joins each point to
    /// its copy in the next instance. The first connector from the selection's first point gets
    /// a distance dimension of `spacing`, and its direction is held: horizontal or vertical when
    /// `direction` is, otherwise parallel, perpendicular or at a measured angle to the
    /// selection's first line. With no line in the selection, an oblique direction stays free.
    /// Every other connector is held parallel and equal to that first one. Copied circles are
    /// held equal to their originals; lines and arcs need nothing more, since their points are held.
    public static func linearPattern(_ sketch: Sketch, entities ids: [SketchEntityID], direction: Vector2,
                                     spacing: Double, count: Int) throws(SketchCommandError) -> SketchEdit {
        let selection = try selection(ids, in: sketch, verb: "pattern")
        try checkCount(count)
        guard spacing > 0, spacing.isFinite else { throw SketchCommandError("The pattern spacing must be greater than 0 mm.") }
        guard let unit = SketchMath.normalized(direction) else { throw SketchCommandError("The pattern needs a direction.") }
        let points = points(of: selection, in: sketch)
        var edited = sketch
        var previous = Dictionary(uniqueKeysWithValues: points.map { ($0, $0) })
        var first: SketchEntityID?
        for instance in 1..<count {
            let offset = unit * (spacing * Double(instance))
            let copy = copy(selection, in: &edited, reversesArcs: false, stays: { _ in false }, transform: { $0 + offset })
            holdRadii(copy, in: &edited)
            for point in points {
                guard let from = previous[point], let to = copy.points[point] else { continue }
                let connector = edited.addLine(from: from, to: to, isConstruction: true)
                if let first {
                    edited.add(.parallel(first, connector))
                    edited.add(.equal(first, connector))
                } else {
                    first = connector
                    edited.addDimension(.distance(from, to), value: spacing)
                    holdDirection(of: connector, along: unit, selection: selection, in: &edited)
                }
                previous[point] = to
            }
        }
        return SketchEdit(sketch: edited, description: "Linear pattern of \(Self.count(selection.count)) (×\(count))")
    }

    /// `count − 1` copies of the selection rotated about `center` in equal steps round a full turn
    /// (spec §3).
    ///
    /// Every instance is held as an exact rotation, with exactly two rows per copied point. Each
    /// point away from the centre gets a construction spoke from the centre, and so does each of
    /// its copies; a copy's spoke is held equal to the original's spoke, with an angle dimension
    /// of one step from the previous instance's spoke. Points at the centre are shared, so arcs
    /// and circles centred on it stay concentric. Copied circles are held equal to their originals.
    public static func circularPattern(_ sketch: Sketch, entities ids: [SketchEntityID], center: SketchEntityID,
                                       count: Int) throws(SketchCommandError) -> SketchEdit {
        let selection = try selection(ids.filter { $0 != center }, in: sketch, verb: "pattern")
        try checkCount(count)
        guard let pivot = sketch.position(of: center) else { throw SketchCommandError("A circular pattern needs a centre point.") }
        let step = 360 / Double(count)
        let isAtCenter = { (position: Vector2) in (position - pivot).length <= CurveIntersection.tolerance }
        let moving = points(of: selection, in: sketch).filter { sketch.position(of: $0).map { !isAtCenter($0) } ?? false }
        guard !moving.isEmpty else { throw SketchCommandError("Select geometry away from the pattern centre.") }
        var edited = sketch
        var originals: [SketchEntityID: SketchEntityID] = [:]
        for point in moving { originals[point] = edited.addLine(from: center, to: point, isConstruction: true) }
        var previous = originals
        for instance in 1..<count {
            let angle = Double(instance) * step * .pi / 180
            let copy = copy(selection, in: &edited, reversesArcs: false, stays: isAtCenter,
                            transform: { SketchMath.rotated($0, about: pivot, by: angle) })
            holdRadii(copy, in: &edited)
            for point in moving {
                guard let next = copy.points[point], let original = originals[point], let last = previous[point] else { continue }
                let spoke = edited.addLine(from: center, to: next, isConstruction: true)
                edited.add(.equal(original, spoke))
                edited.addDimension(.angle(last, spoke), value: step)
                previous[point] = spoke
            }
        }
        return SketchEdit(sketch: edited, description: "Circular pattern of \(Self.count(selection.count)) (×\(count))")
    }

    static func checkCount(_ count: Int) throws(SketchCommandError) {
        guard count >= 2 else { throw SketchCommandError("A pattern needs at least 2 instances.") }
        guard count <= patternLimit else { throw SketchCommandError("A pattern can have at most \(patternLimit) instances.") }
    }

    /// Equal radii between each copied circle and its original. A circle's radius is its own
    /// unknown; every other curve is fully held by its points.
    static func holdRadii(_ copy: Copy, in sketch: inout Sketch) {
        for pair in copy.curves {
            if case .circle = sketch.entities[pair.copy]?.kind { sketch.add(.equal(pair.original, pair.copy)) }
        }
    }

    /// Holds the first connector of a linear pattern along the pattern direction with one row.
    static func holdDirection(of connector: SketchEntityID, along unit: Vector2, selection: [SketchEntityID],
                              in sketch: inout Sketch) {
        let exact = 1e-12
        if abs(unit.y) <= exact {
            sketch.add(.horizontal(connector))
            return
        }
        if abs(unit.x) <= exact {
            sketch.add(.vertical(connector))
            return
        }
        for line in selection {
            guard case .line(let a, let b)? = sketch.shape(of: line) else { continue }
            let d = b - a
            let degrees = abs(atan2(SketchMath.cross(d, unit), SketchMath.dot(d, unit))) * 180 / .pi
            let angleTolerance = 1e-9
            if degrees <= angleTolerance || degrees >= 180 - angleTolerance {
                sketch.add(.parallel(line, connector))
            } else if abs(degrees - 90) <= angleTolerance {
                sketch.add(.perpendicular(line, connector))
            } else {
                sketch.addDimension(.angle(line, connector), value: degrees)
            }
            return
        }
    }
}
