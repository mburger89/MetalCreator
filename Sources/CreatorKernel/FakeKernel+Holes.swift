import CreatorGeometry
import Foundation

extension FakeKernel {
    /// Whether every hole of `profile` lies inside its outline's bounds. The OCCT kernel refuses a hole outside the
    /// outline, crossing it, or overlapping another (`a hole in the profile is outside the outline or overlaps another
    /// loop`); this stand-in checks what its bounds-only geometry can: each hole's sample points against the outline's
    /// bounds. A hole that crosses the outline inside those bounds, or overlaps another hole, still passes.
    static func holesAreInsideOutline(_ profile: Profile2D) -> Bool {
        guard !profile.holes.isEmpty else { return true }
        let corners = profile.outer.flatMap(\.boundingPoints)
        guard let first = corners.first else { return true }
        var low = first
        var high = first
        for corner in corners {
            low = Vector2(min(low.x, corner.x), min(low.y, corner.y))
            high = Vector2(max(high.x, corner.x), max(high.y, corner.y))
        }
        let slack = 1e-9
        return profile.holes.joined().flatMap(samples).allSatisfy {
            $0.x >= low.x - slack && $0.x <= high.x + slack && $0.y >= low.y - slack && $0.y <= high.y + slack
        }
    }

    /// Points on `segment`: its ends and middle, and eight steps round an arc (a full circle's quadrants included).
    private static func samples(of segment: Segment2D) -> [Vector2] {
        switch segment {
        case .line(let a, let b):
            return [a, (a + b) * 0.5, b]
        case .arc(let center, let radius, let start, let end):
            return (0...8).map { step in
                let angle = start.radians + (end.radians - start.radians) * Double(step) / 8
                return center + Vector2(cos(angle), sin(angle)) * radius
            }
        }
    }
}
