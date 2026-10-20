/// A quadric error metric (Garland and Heckbert; implicit spec §4.5): the sum, over some planes, of the squared distance to each
/// plane, kept as the ten distinct entries of a symmetric 4 × 4 matrix. `error(at:)` is that sum at a point. The planes are unit
/// planes with equal weight, so √error is at least the distance to the farthest plane: a collapse whose √error is within the
/// tolerance leaves its new vertex within the tolerance of every triangle plane it has absorbed.
struct Quadric: Sendable {
    var a2 = 0.0, ab = 0.0, ac = 0.0, ad = 0.0
    var b2 = 0.0, bc = 0.0, bd = 0.0
    var c2 = 0.0, cd = 0.0
    var d2 = 0.0

    init() {}

    /// The quadric of the plane through `point` with the unit `normal`.
    init(normal n: SIMD3<Double>, through point: SIMD3<Double>) {
        let d = -(n * point).sum()
        a2 = n.x * n.x
        ab = n.x * n.y
        ac = n.x * n.z
        ad = n.x * d
        b2 = n.y * n.y
        bc = n.y * n.z
        bd = n.y * d
        c2 = n.z * n.z
        cd = n.z * d
        d2 = d * d
    }

    static func + (lhs: Quadric, rhs: Quadric) -> Quadric {
        var sum = Quadric()
        sum.a2 = lhs.a2 + rhs.a2
        sum.ab = lhs.ab + rhs.ab
        sum.ac = lhs.ac + rhs.ac
        sum.ad = lhs.ad + rhs.ad
        sum.b2 = lhs.b2 + rhs.b2
        sum.bc = lhs.bc + rhs.bc
        sum.bd = lhs.bd + rhs.bd
        sum.c2 = lhs.c2 + rhs.c2
        sum.cd = lhs.cd + rhs.cd
        sum.d2 = lhs.d2 + rhs.d2
        return sum
    }

    static func += (lhs: inout Quadric, rhs: Quadric) {
        lhs = lhs + rhs
    }

    /// The sum of the squared plane distances at `p` (never below 0).
    func error(at p: SIMD3<Double>) -> Double {
        let value = a2 * p.x * p.x + 2 * ab * p.x * p.y + 2 * ac * p.x * p.z + 2 * ad * p.x
            + b2 * p.y * p.y + 2 * bc * p.y * p.z + 2 * bd * p.y
            + c2 * p.z * p.z + 2 * cd * p.z + d2
        return max(value, 0)
    }

    /// The point where the error is least, or `nil` when the planes do not fix one (all parallel, or nearly so).
    func optimum() -> SIMD3<Double>? {
        let det = a2 * (b2 * c2 - bc * bc) - ab * (ab * c2 - bc * ac) + ac * (ab * bc - b2 * ac)
        let scale = (a2 + b2 + c2) * (a2 + b2 + c2) * (a2 + b2 + c2)
        guard scale > 0, abs(det) > 1e-9 * scale else { return nil }
        let (x, y, z) = (-ad, -bd, -cd)
        let dx = x * (b2 * c2 - bc * bc) - ab * (y * c2 - bc * z) + ac * (y * bc - b2 * z)
        let dy = a2 * (y * c2 - bc * z) - x * (ab * c2 - bc * ac) + ac * (ab * z - y * ac)
        let dz = a2 * (b2 * z - y * bc) - ab * (ab * z - y * ac) + x * (ab * bc - b2 * ac)
        return SIMD3(dx / det, dy / det, dz / det)
    }
}
