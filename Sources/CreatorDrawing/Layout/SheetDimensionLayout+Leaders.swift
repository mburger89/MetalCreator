import CreatorGeometry
import Foundation

extension DrawingBuilder {
    /// How far a leader runs from the circle before its shoulder: the placement's offset, never less than two arrowheads.
    func leaderReach(_ placement: DimensionPlacement) -> Double { Swift.max(placement.offset, 2 * style.arrowLength) }

    /// The text of a leader at the far end of its shoulder, on the side the leader points to.
    mutating func shoulderText(_ label: DimensionLabel, knee: Vector2, side: ShoulderSide) {
        let end = Vector2(knee.x + side.sign * style.shoulder, knee.y)
        let w = width(of: label)
        let centre = Vector2(end.x + side.sign * (style.textGap + w / 2), end.y)
        self.label(label, center: centre, angle: 0)
    }

    /// A leader from outside onto a circle of sheet `radius` about `tip` (a chamfer's midpoint with radius 0), with its
    /// arrowhead on the circle pointing at the centre and its text on a shoulder (hole callouts, chamfers, small diameters).
    mutating func leaderDimension(tip centre: Vector2, radius: Double, label: DimensionLabel, placement: DimensionPlacement) {
        let u = Self.direction(placement.angle)
        let tip = centre + u * radius
        let knee = tip + u * leaderReach(placement)
        let side = ShoulderSide.toward(u)
        leaderGeometry(tip: tip, knee: knee, side: side)
        shoulderText(label, knee: knee, side: side)
    }

    /// Radius and diameter of a circle seen face on (R8).
    mutating func radial(center c: Vector2, radius r: Double, isDiameter: Bool, label: DimensionLabel, placement: DimensionPlacement) {
        let u = Self.direction(placement.angle)
        let tip = c + u * r
        let w = width(of: label)
        let isISO = style.standard == .iso
        if isDiameter {
            if isISO && 2 * r >= w + 2 * style.arrowLength + 2 {
                let other = c - u * r
                drawing.dimensionLine = [tip, other]
                line(tip, other)
                arrow(tip: tip, back: u * -1)
                arrow(tip: other, back: u)
                let angle = Self.folded(atan2(u.y, u.x))
                let up = Vector2(-sin(angle), cos(angle))
                self.label(label, center: c + up * (style.textLift + height / 2), angle: angle)
            } else {
                leaderDimension(tip: c, radius: r, label: label, placement: placement)
            }
            return
        }
        // A radius: the line from the centre through the arc point, one head at the arc pointing out.
        arrow(tip: tip, back: u * -1)
        if isISO {
            let near = Swift.max(placement.offset, style.textGap)
            line(c, tip + u * (near + w))
            let angle = Self.folded(atan2(u.y, u.x))
            let up = Vector2(-sin(angle), cos(angle))
            self.label(label, center: tip + u * (near + w / 2) + up * (style.textLift + height / 2), angle: angle)
        } else {
            let knee = tip + u * leaderReach(placement)
            let side = ShoulderSide.toward(u)
            line(c, knee)
            line(knee, Vector2(knee.x + side.sign * style.shoulder, knee.y))
            shoulderText(label, knee: knee, side: side)
        }
    }
}
