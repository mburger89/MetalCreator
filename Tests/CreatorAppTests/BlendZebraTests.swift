import CreatorGeometry
import CreatorImplicit
import CreatorViewport
import Foundation
import Testing

/// A G2 blend leaves no kink in a zebra stripe where it meets the surfaces it joins (G-a of the G2 surfacing spec): the reflection's
/// angle, which `ZebraBand` turns into stripes, changes at the same rate on both sides of the blend's edge. A G1 blend's rate jumps.
/// (This is in CreatorAppTests because it needs both `CreatorImplicit` and `CreatorViewport`.)
struct BlendZebraTests {
    static let radius = 10.0
    static let width = 4.0

    static func move(_ x: Double) -> RigidMove {
        RigidMove(origin: Vector3(x, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
    }

    static func union(_ continuity: BlendContinuity) -> ImplicitSolid {
        let a = ImplicitSolid.moved(.sphere(radius: radius), Self.move(-6))
        let b = ImplicitSolid.moved(.sphere(radius: radius), Self.move(6))
        return .union([a, b], blend: .constant(width), continuity: continuity)
    }

    /// The surface point on the ray from the origin at `angle` from +y towards +x, in the xy plane.
    static func surface(_ solid: ImplicitSolid, angle: Double) -> Vector3 {
        let direction = Vector3(sin(angle), cos(angle), 0)
        var low = 0.0, high = 20.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if solid.signedDistance(at: direction * mid) < 0 { low = mid } else { high = mid }
        }
        return direction * ((low + high) / 2)
    }

    static func normal(_ solid: ImplicitSolid, at p: Vector3) -> Vector3 {
        let e = 1e-5
        let gradient = Vector3(
            solid.signedDistance(at: p + Vector3(e, 0, 0)) - solid.signedDistance(at: p - Vector3(e, 0, 0)),
            solid.signedDistance(at: p + Vector3(0, e, 0)) - solid.signedDistance(at: p - Vector3(0, e, 0)),
            0)
        return gradient * (1 / gradient.length)
    }

    /// The stripe phase of the surface at `angle`, read back through `ZebraBand.value` by bisection on the black share: the band is 0
    /// below the share and 1 above it, so the share where it flips is the phase's fraction. The eye is turned a radian off +y so the
    /// reflection's angle stays positive on the right half of the profile, clear of the wrap at 0.
    static func phase(_ solid: ImplicitSolid, angle: Double) -> Double {
        let n = normal(solid, at: surface(solid, angle: angle))
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let share = (low + high) / 2
            let zebra = ViewportZebra(direction: .vertical, stripes: 1, blackShare: share)
            let value = ZebraBand.value(normal: n, toEye: Vector3(-sin(1.0), cos(1.0), 0), right: Vector3(1, 0, 0), up: Vector3(0, 0, 1),
                                        back: Vector3(0, 1, 0), zebra: zebra)
            if value == 0 { high = share } else { low = share }
        }
        return (low + high) / 2
    }

    /// The angle at which the blend begins: where the two spheres' distances differ by the blend width.
    static func edge(_ solid: ImplicitSolid) -> Double {
        func gap(_ angle: Double) -> Double {
            let p = surface(solid, angle: angle)
            return abs((p - Vector3(-6, 0, 0)).length - (p - Vector3(6, 0, 0)).length) - width
        }
        var low = 0.0, high = 1.0 // gap(0) < 0 on the crease; positive far enough round
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if gap(mid) < 0 { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// The relative jump of the phase's rate of change across the blend's edge.
    static func rateJump(_ continuity: BlendContinuity) -> Double {
        let solid = union(continuity)
        let edgeAngle = edge(solid)
        let step = 0.004
        let inside = (phase(solid, angle: edgeAngle - 0.002) - phase(solid, angle: edgeAngle - 0.002 - step)) / step
        let outside = (phase(solid, angle: edgeAngle + 0.002 + step) - phase(solid, angle: edgeAngle + 0.002)) / step
        return abs(outside - inside) / abs(outside)
    }

    @Test func aG2UnionHasNoZebraKink() {
        let g1 = Self.rateJump(.g1), g2 = Self.rateJump(.g2)
        #expect(g1 > 0.3, "a G1 blend's stripes bend sharply at the edge: \(g1)")
        #expect(g2 < 0.1, "a G2 blend's stripes carry on: \(g2)")
    }
}
