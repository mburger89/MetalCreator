import Foundation
import CreatorGeometry
import CreatorGraph

/// Everything that shapes one hole's tool (patterns spec §5), so holes of one size share one tool (§7). A setting the
/// style doesn't use is zeroed, so two plain holes with different counterbore settings are the same size.
struct HoleSize: Hashable, Sendable {
    let diameter: Double
    let depth: Double
    let style: HoleStyle
    let counterboreDiameter: Double
    let counterboreDepth: Double
    let countersinkDiameter: Double
    let countersinkAngle: Angle

    init(diameter: Double, depth: Double, style: HoleStyle, counterbore: (diameter: Double, depth: Double),
         countersink: (diameter: Double, angle: Angle)) {
        self.diameter = diameter
        self.depth = depth
        self.style = style
        counterboreDiameter = style == .counterbore ? counterbore.diameter : 0
        counterboreDepth = style == .counterbore ? counterbore.depth : 0
        countersinkDiameter = style == .countersink ? countersink.diameter : 0
        countersinkAngle = style == .countersink ? countersink.angle : Angle(radians: 0)
    }

    /// How deep the countersink's cone runs: from its diameter down to the hole's, at its half angle.
    var countersinkDepth: Double {
        (countersinkDiameter - diameter) / 2 / tan(countersinkAngle.radians / 2)
    }

    /// The hole's outline in (radius, height) with the mouth at height 0 and the hole running down to −`depth`,
    /// closed along the axis. Revolved about the Z axis it is the tool; its segments are the tags' `side(k)` roles:
    /// the mouth's top disc is 0, and the bore is the segment before the bottom.
    var outline: [Vector2] {
        let r = diameter / 2
        switch style {
        case .plain:
            return [Vector2(0, 0), Vector2(r, 0), Vector2(r, -depth), Vector2(0, -depth)]
        case .counterbore:
            let c = counterboreDiameter / 2
            return [Vector2(0, 0), Vector2(c, 0), Vector2(c, -counterboreDepth), Vector2(r, -counterboreDepth),
                    Vector2(r, -depth), Vector2(0, -depth),
            ]
        case .countersink:
            let s = countersinkDiameter / 2
            return [Vector2(0, 0), Vector2(s, 0), Vector2(r, -countersinkDepth), Vector2(r, -depth), Vector2(0, -depth)]
        }
    }

    /// The reason this size can't be made, worded for instance `path`, or `nil` if it can.
    func problem(at path: String) -> String? {
        guard diameter.isFinite, diameter > 0 else { return "Hole \(path): the diameter must be greater than 0 mm." }
        guard depth.isFinite, depth > 0 else { return "Hole \(path): the depth must be greater than 0 mm." }
        switch style {
        case .plain:
            return nil
        case .counterbore:
            guard counterboreDiameter.isFinite, counterboreDiameter > diameter else {
                return "Hole \(path): the counterbore must be wider than the hole."
            }
            guard counterboreDepth.isFinite, counterboreDepth > 0, counterboreDepth < depth else {
                return counterboreDepth > 0 ? "Hole \(path): the counterbore must be shallower than the hole."
                    : "Hole \(path): the counterbore depth must be greater than 0 mm."
            }
            return nil
        case .countersink:
            guard countersinkDiameter.isFinite, countersinkDiameter > diameter else {
                return "Hole \(path): the countersink must be wider than the hole."
            }
            guard countersinkAngle.degrees.isFinite, countersinkAngle.degrees > 0, countersinkAngle.degrees < 180 else {
                return "Hole \(path): the countersink angle must be between 0° and 180°."
            }
            return countersinkDepth < depth ? nil : "Hole \(path): the countersink must be shallower than the hole."
        }
    }
}
