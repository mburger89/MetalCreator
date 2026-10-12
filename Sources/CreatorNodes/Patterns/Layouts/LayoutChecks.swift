import CreatorGeometry
import CreatorGraph

/// The checks every layout node makes of its inputs, so each refuses a bad one in the same words (patterns spec §3).
enum LayoutChecks {
    /// What a layout says when a list is wired into one of its single-valued inputs (`NodeDefinition.singleValuesRefusal`): a
    /// layout makes one tree of placements, it does not run once per value.
    static func singleValues(_ node: String) -> String {
        "\(node) takes single values, not lists: wire one value into each input, or pick one out of the list first with List Item."
    }

    /// A count that isn't negative.
    static func count(_ value: Int, _ name: SocketName) throws -> Int {
        guard value >= 0 else { throw NodeError.invalidValue("“\(name)” can't be negative.") }
        return value
    }

    /// `a × b` instances, refused over the pattern limit before any of them is made (and without overflowing). Each count is
    /// also checked on its own: a zero count makes the product 0, but the other count would still size a loop of empty rows.
    static func product(_ a: Int, _ b: Int) throws -> Int {
        try PatternLimit.check(a)
        try PatternLimit.check(b)
        let (total, overflowed) = a.multipliedReportingOverflow(by: b)
        guard !overflowed else { throw PatternLimit.refusal }
        try PatternLimit.check(total)
        return total
    }

    /// A number that is finite and at least `minimum`.
    static func number(_ value: Double, _ name: SocketName, atLeast minimum: Double = 0) throws -> Double {
        guard value.isFinite, value >= minimum else {
            throw NodeError.invalidValue("“\(name)” must be \(minimum == 0 ? "0 or more" : "at least \(minimum.display)").")
        }
        return value
    }

    /// A direction with a length, as a unit vector.
    static func direction(_ vector: Vector3, _ name: SocketName) throws -> Vector3 {
        guard vector.isFinite, let unit = vector.normalized else { throw NodeError.invalidValue("“\(name)” can't be zero.") }
        return unit
    }

    /// The placement at `origin` facing `normal` (unit) with x axis `xAxis`.
    static func placement(_ origin: Vector3, normal: Vector3, xAxis: Vector3) -> Scalar {
        .plane(Plane(origin: origin, normal: normal, xAxis: xAxis))
    }
}
