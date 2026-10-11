import CreatorGeometry
import Foundation

/// Everything that shapes one boss's tool (patterns spec §5), so bosses of one size share one tool (§7).
struct BossSize: Hashable, Sendable {
    let diameter: Double
    let height: Double
    /// How much the sides lean in towards the tip.
    let draft: Angle
    /// The radius that rounds the tip's rim; 0 leaves it sharp.
    let tipFillet: Double

    /// The radius at the tip: the base's, less what the draft takes off over the height.
    var tipRadius: Double { diameter / 2 - height * tan(draft.radians) }

    /// The boss's outline in (radius, height), standing on height 0 and growing to `height`, closed along the axis.
    /// Revolved about the Z axis it is the tool; its segments are the tags' `side(k)` roles: the base disc is 0, the
    /// side 1 and the tip disc 2.
    var outline: [Vector2] {
        [Vector2(0, 0), Vector2(diameter / 2, 0), Vector2(tipRadius, height), Vector2(0, height)]
    }

    /// The reason this size can't be made, worded for instance `path`, or `nil` if it can.
    func problem(at path: String) -> String? {
        guard diameter.isFinite, diameter > 0 else { return "Boss \(path): the diameter must be greater than 0 mm." }
        guard height.isFinite, height > 0 else { return "Boss \(path): the height must be greater than 0 mm." }
        guard draft.degrees.isFinite, draft.degrees >= 0, draft.degrees < 90 else {
            return "Boss \(path): the draft must be between 0° and 90°."
        }
        guard tipRadius > 1e-6 else { return "Boss \(path): the draft is too steep: the tip would have no width." }
        guard tipFillet.isFinite, tipFillet >= 0 else { return "Boss \(path): the tip fillet can't be negative." }
        guard tipFillet < tipRadius, tipFillet < height else {
            return "Boss \(path): the tip fillet must be smaller than the tip's radius and the boss's height."
        }
        return nil
    }
}
