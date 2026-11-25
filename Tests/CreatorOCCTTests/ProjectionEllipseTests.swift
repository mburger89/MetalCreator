#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Partial ellipses keep their orientation whichever way a circle's axis points (drawings DR-1, fix round 1).
extension ProjectionTests {
    @Test func everyEllipsePieceLiesOnItsProjectedCircleFromBelowAndAbove() async throws {
        let solid = try await cylinder()
        let s = 1 / 3.0.squareRoot()
        let frames = [
            ProjectionFrame.make(direction: Vector3(-s, s, -s), up: Vector3(0, 0, 1))!,
            ProjectionFrame.make(direction: Vector3(-s, s, s), up: Vector3(0, 0, 1))!,
            ProjectionFrame.make(direction: Vector3(s, -s, s), up: Vector3(0, 0, 1))!,
        ]
        for frame in frames {
            let projection = try await kernel.projection(of: solid, curves: [], frame: frame, options: ProjectionOptions())
            var checked = 0
            var partial = 0
            for line in projection.lines {
                guard case .ellipse(let center, let axis, let major, let minor, let start, let sweep) = line.curve,
                      case .edge(let id)? = line.source, let edge = solid.topology.edge(id) else { continue }
                let height = edge.midpoint.z
                let cross = Vector2(-axis.y, axis.x)
                let right = frame.right, up = frame.up
                for k in 0...8 {
                    let t = start + sweep * Double(k) / 8
                    let p = center + axis * (major * cos(t)) + cross * (minor * sin(t))
                    // Lift the point back to the circle's plane z = height and test the radius.
                    let rx = p.x - right.z * height, ry = p.y - up.z * height
                    let det = right.x * up.y - right.y * up.x
                    let x = (rx * up.y - right.y * ry) / det
                    let y = (right.x * ry - up.x * rx) / det
                    #expect(abs((x * x + y * y).squareRoot() - 5) < 1e-9)
                    checked += 1
                }
                // A mirrored piece would put the far half of a cap where its near half is: the truth is known.
                guard abs(sweep) < 2 * .pi - 1e-9 else { continue }
                let t = start + sweep / 2
                let mid = center + axis * (major * cos(t)) + cross * (minor * sin(t))
                let lx = mid.x - right.z * height, ly = mid.y - up.z * height
                let det = right.x * up.y - right.y * up.x
                let x = (lx * up.y - right.y * ly) / det
                let y = (right.x * ly - up.x * lx) / det
                let facingAway = x * frame.direction.x + y * frame.direction.y > 0
                let nearCap = (height - 10) * frame.direction.z < 0
                #expect(line.visibility == (nearCap || !facingAway ? .visible : .hidden))
                partial += 1
            }
            #expect(checked > 0 && partial > 0)
        }
    }
}
#endif
