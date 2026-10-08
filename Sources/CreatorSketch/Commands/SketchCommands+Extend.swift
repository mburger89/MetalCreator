import CreatorGeometry

extension SketchCommands {
    /// Extends the end of a line or arc nearest `pick` to the first curve it meets (spec §3). The
    /// end must be free: used by no other curve and not coincident with or fixed to anything.
    /// The moved end is shared with, or held on, the curve it reaches.
    public static func extend(_ sketch: Sketch, curve: SketchEntityID, near pick: Vector2) throws(SketchCommandError) -> SketchEdit {
        let shape = try editableShape(sketch, curve, verb: "extended")
        guard case let kind? = sketch.entities[curve]?.kind, !shape.isFullCircle,
              case let (start, end) = endpoints(of: kind), start != end else {
            throw SketchCommandError("Only lines and arcs can be extended.")
        }
        let atEnd = (shape.endPoint - pick).length < (shape.startPoint - pick).length
        let moving = atEnd ? end : start
        let isHeld = sketch.constraints.values.contains { constraint in
            switch constraint {
            case .coincident(let a, let b): a == moving || b == moving
            case .fix(let point, _): point == moving
            default: false
            }
        }
        guard users(of: moving, besides: curve, in: sketch).isEmpty, !isHeld else {
            throw SketchCommandError("That end of \(sketch.label(of: curve)) is connected to other geometry.")
        }
        let probe = extensionProbe(of: shape, atEnd: atEnd, reach: reach(of: sketch))
        var best: (distance: Double, position: Vector2, cutter: SketchEntityID)?
        for other in sketch.curves(includingConstruction: true) where other.source != curve {
            for position in CurveIntersection.points(probe, other.shape) {
                // Arc probes that extend the start run backwards from it.
                let t = probe.nearestParameter(to: position)
                let distance = probe.length(from: 0, to: (atEnd || !isArc(shape)) ? t : probe.parameterEnd - t)
                guard distance > CurveIntersection.tolerance else { continue }
                if best.map({ distance < $0.distance - CurveIntersection.tolerance }) ?? true {
                    best = (distance, position, other.source)
                }
            }
        }
        guard let hit = best else {
            throw SketchCommandError("There is nothing to extend \(sketch.label(of: curve)) to.")
        }
        var edited = sketch
        // Anything that pins the moving end elsewhere would pull it back.
        edited.constraints = edited.constraints.filter { !$0.value.entities.contains(moving) }
        edited.dimensions = edited.dimensions.filter { !$0.value.kind.entities.contains(moving) }
        removeExtentDependent(on: curve, in: &edited)
        if let shared = sharedEndpoint(of: hit.cutter, at: hit.position, in: edited) {
            edited.entities[curve]?.kind = kind.replacingPoint(moving, with: shared)
            edited.removeEntity(moving)
        } else {
            edited.move(moving, to: hit.position)
            edited.add(.pointOn(point: moving, curve: hit.cutter))
        }
        return SketchEdit(sketch: edited, description: "Extend \(sketch.label(of: curve))")
    }

    static func isArc(_ shape: CurveShape) -> Bool {
        if case .arc = shape { return true }
        return false
    }

    /// The curve the end would sweep along: a long ray beyond a line's end, or the rest of an
    /// arc's circle beyond (or before) its span.
    static func extensionProbe(of shape: CurveShape, atEnd: Bool, reach: Double) -> CurveShape {
        switch shape {
        case .line(let a, let b):
            let (from, away) = atEnd ? (b, b - a) : (a, a - b)
            let unit = SketchMath.normalized(away) ?? Vector2(1, 0)
            return .line(from, from + unit * reach)
        case .arc(let center, let radius, let start, let sweep):
            let rest = CurveShape.fullTurn - sweep - 1e-9
            return atEnd ? .arc(center: center, radius: radius, start: start + sweep, sweep: rest)
                : .arc(center: center, radius: radius, start: start - rest, sweep: rest)
        }
    }

    /// Far enough to cross the whole sketch: four times its bounding diagonal, at least 1 m.
    static func reach(of sketch: Sketch) -> Double {
        let points = sketch.curves(includingConstruction: true).flatMap { curve -> [Vector2] in
            switch curve.shape {
            case .line(let a, let b): [a, b]
            case .arc(let c, let r, _, _): [c + Vector2(-r, -r), c + Vector2(r, r)]
            }
        }
        guard let first = points.first else { return 1000 }
        var (low, high) = (first, first)
        for p in points {
            low = Vector2(min(low.x, p.x), min(low.y, p.y))
            high = Vector2(max(high.x, p.x), max(high.y, p.y))
        }
        return max(1000, 4 * (high - low).length)
    }
}
