import CreatorGeometry

extension TermBuilder {
    func isSpline(_ id: SketchEntityID) -> Bool {
        if case .spline? = sketch.entities[id]?.kind { true } else { false }
    }

    /// Tangent (G1) or Curvature (G2) between a spline and a line, an arc or another spline, at every end they share (one
    /// or, for a closed pair, two). Tangent holds the outgoing directions parallel; Curvature that and the outgoing signed
    /// curvatures equal (0 for a line, 1/r for an arc, a spline's own). The spline's handles at the end must be active
    /// (the editor activates them): the tangent handle for Tangent, both for Curvature.
    func splineJoints(_ a: SketchEntityID, _ b: SketchEntityID, _ ref: SketchConstraintRef,
                      curvature: Bool) throws(SolveFailure) -> [Equation] {
        let needs = "a spline end and a line, an arc or another spline that ends there"
        if curvature, !isSpline(a), !isSpline(b) {
            let isLineAndArc = (isLine(a) && sketch.isArc(b)) || (isLine(b) && sketch.isArc(a))
            if isLineAndArc { throw SolveFailure(reason: "A line and an arc can't meet with equal curvature.") }
            throw wrongKind(ref, needs: needs, blaming: [a, b])
        }
        let joints = sketch.curveEnds(of: a).filter { sketch.curveEnds(of: b).contains($0) }
        var seen = Set<SketchEntityID>()
        let unique = joints.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else {
            throw SolveFailure(reason: "\(sketch.label(of: ref)) needs the two curves to end at the same point.")
        }
        var equations: [Equation] = []
        for joint in unique {
            let first = try jointSide(a, at: joint, ref, curvature: curvature)
            let second = try jointSide(b, at: joint, ref, curvature: curvature)
            let scale = jointScale(a, b, at: joint)
            equations.append(.jointTangent(first, second, scale: scale))
            if curvature {
                let continues = SketchMath.dot(first.direction(x0), second.direction(x0)) <= 0
                equations.append(.jointCurvature(first, second, branch: continues ? -1 : 1, scale: scale * scale))
            }
        }
        return equations
    }

    /// The curve `id` as seen at `joint`, one of its ends. A spline needs the handles active at that end.
    func jointSide(_ id: SketchEntityID, at joint: SketchEntityID, _ ref: SketchConstraintRef,
                   curvature: Bool) throws(SolveFailure) -> JointSide {
        let needs = "a spline end and a line, an arc or another spline that ends there"
        switch sketch.entities[id]?.kind {
        case .line(let start, let end):
            let far = start == joint ? end : start
            return .line(from: try point(joint, ref: ref, needs: needs), to: try point(far, ref: ref, needs: needs))
        case .arc(_, let start, _):
            return .arc(joint: try point(joint, ref: ref, needs: needs), circle: try circle(id, ref: ref, needs: needs),
                        sense: start == joint ? 1 : -1)
        case .spline(let points, _):
            let index = points.first == joint ? 0 : points.count - 1
            guard let tangent = layout.handleColumn(id, index, .tangent) else {
                throw inactiveHandle("tangent", of: id, ref)
            }
            var second: Int?
            if curvature {
                second = layout.handleColumn(id, index, .curvature)
                if second == nil {
                    throw inactiveHandle("curvature", of: id, ref)
                }
            }
            return .spline(tangent: tangent, curvature: second, reversed: index != 0)
        default:
            throw wrongKind(ref, needs: needs, blaming: [id])
        }
    }

    private func inactiveHandle(_ name: String, of id: SketchEntityID, _ ref: SketchConstraintRef) -> SolveFailure {
        SolveFailure(reason: "\(sketch.label(of: ref)) needs the \(name) handle at the end of \(sketch.label(of: id)) to be active.")
    }

    /// The length that turns an angle (and, squared, a curvature) into millimetres: the chord of the spline's span at the
    /// joint at the warm start, 1 mm when it has none.
    func jointScale(_ a: SketchEntityID, _ b: SketchEntityID, at joint: SketchEntityID) -> Double {
        let id = isSpline(a) ? a : b
        guard let (points, _) = sketch.splineParts(of: id), points.count >= 2 else { return 1 }
        let neighbour = points.first == joint ? points[1] : points[points.count - 2]
        guard let c = layout.pointColumns[joint], let n = layout.pointColumns[neighbour] else { return 1 }
        let length = (Vector2(x0[c], x0[c + 1]) - Vector2(x0[n], x0[n + 1])).length
        return length > 1e-9 ? length : 1
    }
}
