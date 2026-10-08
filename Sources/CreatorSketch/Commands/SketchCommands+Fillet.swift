import CreatorGeometry
import Foundation

extension SketchCommands {
    /// Rounds the corner where exactly two lines meet at `corner` (spec §3): the lines are trimmed
    /// back to the tangent points and joined by a tangent arc with a radius dimension. The corner
    /// point and everything on it are removed, as are the lines' lengths, equal-length and
    /// midpoint constraints, which no longer describe the trimmed lines.
    public static func fillet(_ sketch: Sketch, corner: SketchEntityID, radius: Double) throws(SketchCommandError) -> SketchEdit {
        guard radius > 0, radius.isFinite else { throw SketchCommandError("The fillet radius must be greater than 0 mm.") }
        let lines = users(of: corner, in: sketch)
        guard lines.count == 2, let p = sketch.position(of: corner),
              case .line(let s1, let e1)? = sketch.entities[lines[0]]?.kind,
              case .line(let s2, let e2)? = sketch.entities[lines[1]]?.kind,
              let a = sketch.position(of: s1 == corner ? e1 : s1), let b = sketch.position(of: s2 == corner ? e2 : s2),
              let u1 = SketchMath.normalized(a - p), let u2 = SketchMath.normalized(b - p) else {
            throw SketchCommandError("A fillet needs a corner where exactly two lines meet.")
        }
        let between = acos(min(1, max(-1, SketchMath.dot(u1, u2))))
        guard sin(between) > 1e-9 else { throw SketchCommandError("The lines at that corner are parallel.") }
        let half = between / 2
        let setback = radius / tan(half)
        let shorter = min((a - p).length, (b - p).length)
        guard setback < shorter - CurveIntersection.tolerance else {
            let largest = (shorter * tan(half) * 10).rounded() / 10
            throw SketchCommandError("Radius \(radius.sketchDisplay) mm is too large for this corner (max ≈ \(largest.sketchDisplay) mm).")
        }
        guard let bisector = SketchMath.normalized(u1 + u2) else {
            throw SketchCommandError("The lines at that corner are parallel.")
        }
        let (firstPosition, secondPosition) = (p + u1 * setback, p + u2 * setback)
        let centerPosition = p + bisector * (radius / sin(half))
        var edited = sketch
        let first = newPoint(at: firstPosition, in: &edited)
        let second = newPoint(at: secondPosition, in: &edited)
        let center = newPoint(at: centerPosition, in: &edited)
        for (line, tangentPoint) in [(lines[0], first), (lines[1], second)] {
            if let kind = edited.entities[line]?.kind {
                edited.entities[line]?.kind = kind.replacingPoint(corner, with: tangentPoint)
            }
            removeExtentDependent(on: line, in: &edited)
        }
        edited.removeEntity(corner)
        // Counter-clockwise from whichever tangent point makes the short arc.
        let isCounterClockwise = SketchMath.cross(firstPosition - centerPosition, secondPosition - centerPosition) > 0
        let isConstruction = lines.allSatisfy { sketch.entities[$0]?.isConstruction ?? false }
        let arc = edited.addArc(center: center, start: isCounterClockwise ? first : second, end: isCounterClockwise ? second : first,
                                isConstruction: isConstruction)
        edited.add(.tangent(lines[0], arc))
        edited.add(.tangent(lines[1], arc))
        edited.addDimension(.radius(arc), value: radius)
        return try edit(from: sketch, to: edited, description: "Fillet \(sketch.label(of: corner)) (\(radius.sketchDisplay) mm)")
    }
}
