import CreatorGeometry

extension SketchCommands {
    /// Removes the span of `curve` around `pick` between its nearest intersections with any other
    /// curve (spec §3). A span reaching a free end shortens the curve, a span in the middle splits
    /// it in two (the new piece is held collinear or co-circular with the first), a curve with no
    /// intersections is deleted, and a circle becomes an arc. New endpoints are shared with the
    /// cutting curve's endpoint when one is there, else held on the cutter by point-on.
    public static func trim(_ sketch: Sketch, curve: SketchEntityID, near pick: Vector2) throws(SketchCommandError) -> SketchEdit {
        let shape = try editableShape(sketch, curve, verb: "trimmed")
        let description = "Trim \(sketch.label(of: curve))"
        let cuts = cuts(of: shape, curve: curve, in: sketch)
        var edited = sketch
        let pickT = shape.nearestParameter(to: pick)
        guard case let kind? = sketch.entities[curve]?.kind else { throw SketchCommandError("That curve no longer exists.") }

        if shape.isFullCircle {
            guard cuts.count >= 2, case .circle(let center, _) = kind else {
                edited.removeEntity(curve)
                edited.removeOrphanPoints(kind.referencedPoints)
                return SketchEdit(sketch: edited, description: description)
            }
            // The removed span runs counter-clockwise from the last cut at or before the pick to the next.
            let index = cuts.lastIndex { $0.t <= pickT } ?? cuts.count - 1
            let (removedFrom, removedTo) = (cuts[index], cuts[(index + 1) % cuts.count])
            let start = point(at: removedTo.position, on: removedTo.cutter, in: &edited)
            let end = point(at: removedFrom.position, on: removedFrom.cutter, in: &edited)
            edited.entities[curve]?.kind = .arc(center: center, start: start, end: end)
            edited.solved[curve] = nil
            return SketchEdit(sketch: edited, description: description)
        }

        let lower = cuts.last { $0.t < pickT }
        let upper = cuts.first { $0.t > pickT }
        let (oldStart, oldEnd) = endpoints(of: kind)
        switch (lower, upper) {
        case (nil, nil):
            edited.removeEntity(curve)
            edited.removeOrphanPoints(kind.referencedPoints)
        case (nil, let upper?):
            let start = point(at: upper.position, on: upper.cutter, in: &edited)
            edited.entities[curve]?.kind = kind.replacingPoint(oldStart, with: start)
            removeTangents(on: curve, sharing: oldStart, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            edited.removeOrphanPoints([oldStart])
        case (let lower?, nil):
            let end = point(at: lower.position, on: lower.cutter, in: &edited)
            edited.entities[curve]?.kind = kind.replacingPoint(oldEnd, with: end)
            removeTangents(on: curve, sharing: oldEnd, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            edited.removeOrphanPoints([oldEnd])
        case (let lower?, let upper?):
            let end = point(at: lower.position, on: lower.cutter, in: &edited)
            let start = point(at: upper.position, on: upper.cutter, in: &edited)
            let isConstruction = sketch.entities[curve]?.isConstruction ?? false
            edited.entities[curve]?.kind = kind.replacingPoint(oldEnd, with: end)
            let piece = edited.add(SketchEntity(kind.replacingPoint(oldStart, with: start), isConstruction: isConstruction))
            moveTangents(on: curve, sharing: oldEnd, to: piece, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            if case .line = kind {
                edited.add(.pointOn(point: start, curve: curve))
                edited.add(.pointOn(point: oldEnd, curve: curve))
            } else {
                // Arc pieces already share the centre.
                edited.add(.equal(curve, piece))
            }
        }
        return SketchEdit(sketch: edited, description: description)
    }

    struct Cut {
        var t: Double
        var position: Vector2
        var cutter: SketchEntityID
    }

    /// Where every other curve (construction and projected included) crosses `shape`, strictly
    /// inside it, sorted by parameter, one cut per place (the lowest-ID cutter wins).
    static func cuts(of shape: CurveShape, curve: SketchEntityID, in sketch: Sketch) -> [Cut] {
        var cuts: [Cut] = []
        for other in sketch.curves(includingConstruction: true) where other.source != curve {
            for position in CurveIntersection.points(shape, other.shape) {
                let t = shape.isFullCircle ? SketchMath.wrapped(shape.parameter(of: position)) : shape.nearestParameter(to: position)
                let interior = shape.isFullCircle
                    || (shape.length(from: 0, to: t) > CurveIntersection.tolerance
                        && shape.length(from: t, to: shape.parameterEnd) > CurveIntersection.tolerance)
                if interior { cuts.append(Cut(t: t, position: position, cutter: other.source)) }
            }
        }
        cuts.sort { ($0.t, $0.cutter) < ($1.t, $1.cutter) }
        var distinct: [Cut] = []
        for cut in cuts where distinct.last.map({ shape.length(from: $0.t, to: cut.t) > CurveIntersection.tolerance }) ?? true {
            distinct.append(cut)
        }
        if shape.isFullCircle, distinct.count > 1, let first = distinct.first, let last = distinct.last,
           shape.length(from: last.t, to: first.t + CurveShape.fullTurn) <= CurveIntersection.tolerance {
            distinct.removeLast()
        }
        return distinct
    }

    /// The (start, end) points of a line or arc.
    static func endpoints(of kind: SketchEntityKind) -> (SketchEntityID, SketchEntityID) {
        switch kind {
        case .line(let start, let end), .arc(_, let start, let end): (start, end)
        default: (SketchEntityID(0), SketchEntityID(0))
        }
    }
}
