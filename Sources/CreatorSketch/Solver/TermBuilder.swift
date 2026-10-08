import CreatorGeometry
import Foundation

/// Turns a sketch's constraints, driving dimensions and arcs into equations over the global
/// unknowns. Choices that pick a solution branch (which side of a line, internal or external
/// tangency) are read from the warm start `x0`, which is what keeps solves branch-stable
/// (spec §4). An angle's sense is stored on its dimension (`AngleSense`), falling back to the
/// warm start only for a dimension that has none yet.
struct TermBuilder {
    let sketch: Sketch
    let layout: UnknownLayout
    let x0: [Double]

    struct Output: Sendable {
        var terms: [SolverTerm]
        /// Constraints and dimensions skipped because they touch a suspended projected edge.
        var suspended: [SketchConstraintRef]
    }

    func build() throws(SolveFailure) -> Output {
        try validateEntities()
        var terms: [SolverTerm] = []
        var suspended: [SketchConstraintRef] = []
        for id in sketch.constraintIDs {
            guard let constraint = sketch.constraints[id] else { continue }
            let ref = SketchConstraintRef.constraint(id)
            try requireExisting(constraint.entities, ref)
            if touchesSuspended(constraint.entities) {
                suspended.append(ref)
                continue
            }
            for equation in try equations(for: constraint, ref) where !isTriviallyMet(equation) {
                terms.append(SolverTerm(role: .user(ref), equation: equation))
            }
        }
        for id in sketch.dimensionIDs {
            guard let dimension = sketch.dimensions[id], dimension.isDriving else { continue }
            let ref = SketchConstraintRef.dimension(id)
            try requireExisting(dimension.kind.entities, ref)
            if touchesSuspended(dimension.kind.entities) {
                suspended.append(ref)
                continue
            }
            try validate(dimension)
            let equation = try equation(for: dimension, ref)
            if !isTriviallyMet(equation) { terms.append(SolverTerm(role: .user(ref), equation: equation)) }
        }
        for id in sketch.entityIDs {
            guard case .arc(let center, let start, let end) = sketch.entities[id]?.kind else { continue }
            let equation = Equation.arcRadius(center: try point(center, ref: nil, needs: ""),
                                              start: try point(start, ref: nil, needs: ""),
                                              end: try point(end, ref: nil, needs: ""))
            terms.append(SolverTerm(role: .implicit, equation: equation))
        }
        return Output(terms: terms, suspended: suspended)
    }

    /// Constants agreeing to within this (mm) already hold. The same as the solver's satisfied
    /// tolerance (`ComponentSolver.satisfiedTolerance`, Task 5).
    static let metTolerance = 1e-7

    /// True for a row that holds whatever the unknowns are: the same point twice (coincident,
    /// horizontal or vertical points, or concentric curves that already share a centre), the
    /// same line or circle twice (parallel, equal, a 0° or 180° angle), or constants only that
    /// already agree (horizontal on a projected edge that is horizontal). Such a row's Jacobian
    /// is identically zero, so keeping it would always read as redundancy; it is dropped, and
    /// takes no part in DOF, redundancy or conflicts. Constants that disagree are kept, so the
    /// solve reports them as a conflict ("… can't be met.").
    func isTriviallyMet(_ equation: Equation) -> Bool {
        switch equation {
        case .coincident(let p, let q), .horizontal(let p, let q), .vertical(let p, let q):
            if p == q { return true }
        case .parallel(let a, let b, _), .equalLength(let a, let b):
            if a == b { return true }
        case .equalRadius(let a, let b):
            if a == b { return true }
        case .angle(let a, let b, let target, _):
            // The same line twice is always at 0°, met only by a directed target of 0.
            if a == b, abs(AngleSense.wrappedToHalfTurn(target)) <= 1e-12 { return true }
        default:
            break
        }
        return equation.columns.isEmpty
            && equation.rows(x0).allSatisfy { abs($0.value) <= Self.metTolerance }
    }

    // MARK: Operands

    func wrongKind(_ ref: SketchConstraintRef?, needs: String) -> SolveFailure {
        let name = ref.map { sketch.label(of: $0) } ?? "A constraint"
        return SolveFailure(reason: "\(name) needs \(needs).")
    }

    func point(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> PointOperand {
        guard let column = layout.pointColumns[id] else { throw wrongKind(ref, needs: needs) }
        return .unknown(column: column)
    }

    func line(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> LineOperand {
        switch sketch.entities[id]?.kind {
        case .line(let start, let end):
            return LineOperand(start: try point(start, ref: ref, needs: needs), end: try point(end, ref: ref, needs: needs))
        case .projected(let source):
            if case .line(let a, let b) = source.curve { return LineOperand(start: .constant(a), end: .constant(b)) }
            throw wrongKind(ref, needs: needs)
        default:
            throw wrongKind(ref, needs: needs)
        }
    }

    func circle(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> CircleOperand {
        switch sketch.entities[id]?.kind {
        case .arc(let center, let start, let end):
            let startPoint = try point(start, ref: ref, needs: needs)
            return CircleOperand(center: try point(center, ref: ref, needs: needs), radius: .through(startPoint),
                                 endpoints: [startPoint, try point(end, ref: ref, needs: needs)])
        case .circle(let center, _):
            guard let column = layout.radiusColumns[id] else { throw wrongKind(ref, needs: needs) }
            return CircleOperand(center: try point(center, ref: ref, needs: needs), radius: .unknown(column: column), endpoints: [])
        case .projected(let source):
            switch source.curve {
            case .arc(let center, let radius, _, _), .circle(let center, let radius):
                return CircleOperand(center: .constant(center), radius: .constant(radius), endpoints: [])
            case .line:
                throw wrongKind(ref, needs: needs)
            }
        default:
            throw wrongKind(ref, needs: needs)
        }
    }

    func isLine(_ id: SketchEntityID) -> Bool {
        switch sketch.entities[id]?.kind {
        case .line: true
        case .projected(let source): if case .line = source.curve { true } else { false }
        default: false
        }
    }

    func isCircular(_ id: SketchEntityID) -> Bool {
        switch sketch.entities[id]?.kind {
        case .arc, .circle: true
        case .projected(let source): if case .line = source.curve { false } else { true }
        default: false
        }
    }

    func isPoint(_ id: SketchEntityID) -> Bool { layout.pointColumns[id] != nil }

    /// The point entity both curves end at, if they share one (lines: start/end; arcs: start/end).
    func sharedEndpoint(_ a: SketchEntityID, _ b: SketchEntityID) -> SketchEntityID? {
        let first = endpoints(of: a)
        return endpoints(of: b).first { first.contains($0) }
    }

    func endpoints(of id: SketchEntityID) -> [SketchEntityID] {
        switch sketch.entities[id]?.kind {
        case .line(let start, let end): [start, end]
        case .arc(_, let start, let end): [start, end]
        default: []
        }
    }

    func center(of id: SketchEntityID) -> SketchEntityID? {
        switch sketch.entities[id]?.kind {
        case .arc(let center, _, _), .circle(let center, _): center
        default: nil
        }
    }

    // MARK: Equations

    /// The mean length of two lines at the warm start, the scale that turns an angle-type
    /// residual into millimetres. 1 mm for degenerate lines.
    func scale(_ a: LineOperand, _ b: LineOperand) -> Double {
        let mean = (a.direction(x0).length + b.direction(x0).length) / 2
        return mean > 1e-9 ? mean : 1
    }

    /// +1 when `p` starts on the left of the line (or on it), −1 on the right.
    func side(_ p: PointOperand, _ line: LineOperand) -> Double {
        Equation.signedDistance(p, line, x0).value < 0 ? -1 : 1
    }

    // One exhaustive case per constraint kind; splitting it would scatter the constraint table.
    // swiftlint:disable:next cyclomatic_complexity
    func equations(for constraint: SketchConstraint, _ ref: SketchConstraintRef) throws(SolveFailure) -> [Equation] {
        switch constraint {
        case .coincident(let a, let b):
            return [.coincident(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .pointOn(let p, let curve):
            let needs = "a point and a curve"
            let operand = try point(p, ref: ref, needs: needs)
            if isLine(curve) { return [.pointOnLine(operand, try line(curve, ref: ref, needs: needs))] }
            return [.pointOnCircle(operand, try circle(curve, ref: ref, needs: needs))]
        case .horizontal(let id):
            let l = try line(id, ref: ref, needs: "a line")
            return [.horizontalLine(l, scale: scale(l, l))]
        case .vertical(let id):
            let l = try line(id, ref: ref, needs: "a line")
            return [.verticalLine(l, scale: scale(l, l))]
        case .horizontalPoints(let a, let b):
            return [.horizontal(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .verticalPoints(let a, let b):
            return [.vertical(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .parallel(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            return [.parallel(first, second, scale: scale(first, second))]
        case .perpendicular(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            return [.perpendicular(first, second, scale: scale(first, second))]
        case .tangent(let a, let b):
            return [try tangent(a, b, ref)]
        case .equal(let a, let b):
            let needs = "two lines or two arcs or circles"
            if isLine(a), isLine(b) {
                return [.equalLength(try line(a, ref: ref, needs: needs), try line(b, ref: ref, needs: needs))]
            }
            guard isCircular(a), isCircular(b) else { throw wrongKind(ref, needs: needs) }
            return [.equalRadius(try circle(a, ref: ref, needs: needs), try circle(b, ref: ref, needs: needs))]
        case .midpoint(let p, let l):
            let needs = "a point and a line"
            return [.midpoint(try point(p, ref: ref, needs: needs), try line(l, ref: ref, needs: needs))]
        case .concentric(let a, let b):
            let needs = "two arcs or circles"
            return [.coincident(try circle(a, ref: ref, needs: needs).center, try circle(b, ref: ref, needs: needs).center)]
        case .symmetric(let a, let b, let l):
            let needs = "two points and a line"
            let equation = Equation.symmetric(try point(a, ref: ref, needs: needs), try point(b, ref: ref, needs: needs),
                                              try line(l, ref: ref, needs: needs))
            return [equation]
        case .fix(let p, let target):
            return [.fix(try point(p, ref: ref, needs: "a point"), target)]
        }
    }

    func tangent(_ a: SketchEntityID, _ b: SketchEntityID, _ ref: SketchConstraintRef) throws(SolveFailure) -> Equation {
        let needs = "a line and an arc or circle, or two arcs or circles"
        if isLine(a) || isLine(b) {
            let (lineID, circleID) = isLine(a) ? (a, b) : (b, a)
            guard !isLine(circleID) else { throw wrongKind(ref, needs: needs) }
            let l = try line(lineID, ref: ref, needs: needs)
            let c = try circle(circleID, ref: ref, needs: needs)
            if let shared = sharedEndpoint(lineID, circleID) {
                return .tangentAtPoint(try point(shared, ref: ref, needs: needs), center: c.center, l)
            }
            return .lineTangent(l, c, side: side(c.center, l))
        }
        let (first, second) = (try circle(a, ref: ref, needs: needs), try circle(b, ref: ref, needs: needs))
        if let shared = sharedEndpoint(a, b) {
            // The shared point lies on the line through both centres.
            return .pointOnLine(try point(shared, ref: ref, needs: needs), LineOperand(start: first.center, end: second.center))
        }
        let distance = (first.center.value(x0) - second.center.value(x0)).length
        let (r1, r2) = (first.radiusValue(x0), second.radiusValue(x0))
        let isInternal = abs(distance - abs(r1 - r2)) < abs(distance - (r1 + r2))
        return .circleTangent(first, second, isInternal: isInternal, sign: r1 >= r2 ? 1 : -1)
    }

    func equation(for dimension: SketchDimension, _ ref: SketchConstraintRef) throws(SolveFailure) -> Equation {
        switch dimension.kind {
        case .distance(let a, let b):
            let needs = "two points, or a point and a line"
            if isPoint(a), isPoint(b) {
                return .distance(try point(a, ref: ref, needs: needs), try point(b, ref: ref, needs: needs), dimension.value)
            }
            let (pointID, lineID) = isPoint(a) ? (a, b) : (b, a)
            let p = try point(pointID, ref: ref, needs: needs)
            let l = try line(lineID, ref: ref, needs: needs)
            return .lineDistance(p, l, dimension.value, side: side(p, l))
        case .length(let id):
            return .length(try line(id, ref: ref, needs: "a line"), dimension.value)
        case .radius(let id):
            return .radius(try circle(id, ref: ref, needs: "an arc or circle"), dimension.value)
        case .diameter(let id):
            return .radius(try circle(id, ref: ref, needs: "an arc or circle"), dimension.value / 2)
        case .angle(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            let sense = dimension.angleSense
                ?? AngleSense.nearest(from: first.direction(x0), to: second.direction(x0), degrees: dimension.value)
            return .angle(first, second, target: sense.directedTarget(degrees: dimension.value), scale: scale(first, second))
        }
    }
}
