import CreatorGeometry
import Foundation

/// The pointer readout's words (user, 2026-10-09): one decimal, US digits like the app's messages, never grouped (the
/// point readout separates its coordinates with a comma) and never "−0.0".
enum ReadoutText {
    static let locale = Locale(identifier: "en_US")

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return (rounded == 0 ? 0 : rounded).formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }

    /// An angle in degrees, wrapped into 0 ≤ angle < 360 after rounding (so 359.96° reads "0.0°").
    static func degrees(_ radians: Double) -> String {
        var degrees = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        if (degrees * 10).rounded() / 10 >= 360 { degrees = 0 }
        return "\(number(degrees))°"
    }

    /// "24.5 mm · 30.0°": a line's length and its angle, counter-clockwise from the plane's +x axis.
    static func line(from start: Vector2, to end: Vector2) -> String {
        let delta = end - start
        return "\(number(delta.length)) mm · \(degrees(atan2(delta.y, delta.x)))"
    }

    /// "⌀ 20.0 mm".
    static func diameter(_ radius: Double) -> String {
        "⌀ \(number(radius * 2)) mm"
    }

    /// "R 12.0 mm".
    static func radius(_ radius: Double) -> String {
        "R \(number(radius)) mm"
    }

    /// "R 12.0 mm · 90.0°": an arc's radius and its sweep, counter-clockwise from `start` to `end` around `center`.
    static func arc(center: Vector2, start: Vector2, end: Vector2) -> String {
        let from = start - center
        let to = end - center
        return "\(radius(from.length)) · \(degrees(atan2(to.y, to.x) - atan2(from.y, from.x)))"
    }

    /// "12.0, 8.5".
    static func position(_ p: Vector2) -> String {
        "\(number(p.x)), \(number(p.y))"
    }
}
