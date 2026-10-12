import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// Placements on a circle, or on several (patterns spec §3): `count` of them about `centre`, turning about `axis`, at
/// `radius`, over a `sweep` angle from `startAngle` (measured from the direction Plane from Face would give an x axis for
/// that axis). A full sweep of 360° spaces them evenly without repeating the first; a smaller one puts the last at the end
/// of the sweep. Each faces along the axis; with `rotate` its x axis points outwards from the centre, so a slot in it runs
/// along the radius, and without it every x axis is the same.
///
/// `rings` makes concentric rings: ring `k` has radius `radius + k × radiusStep` and `count + k × countStep` placements
/// (a step of 6 makes a ring of 6 inside one of 12). One branch per ring, so a placement is `{ring;index}`: always a tree,
/// even for one ring, so adding a ring renames no other path.
///
/// More than 2,000 placements in all refuses ("Patterns are limited to 2,000 instances.").
public enum CircularPatternNode: NodeDefinition {
    public static let typeID = "creator.circularPattern"
    public static let displayName = "Circular Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("centre", .vector, defaultValue: .vector(.zero)),
        SocketSpec("axis", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("radius", .number, defaultValue: .number(20), unit: .millimetres, range: 0...200),
        SocketSpec("count", .integer, defaultValue: .integer(6), unit: .count),
        SocketSpec("sweep", .number, defaultValue: .number(360), unit: .degrees, range: -360...360),
        SocketSpec("startAngle", .number, defaultValue: .number(0), unit: .degrees, range: -360...360),
        SocketSpec("rotate", .bool, defaultValue: .bool(true)),
        SocketSpec("rings", .integer, defaultValue: .integer(1), unit: .count),
        SocketSpec("radiusStep", .number, defaultValue: .number(10), unit: .millimetres, range: -100...100),
        SocketSpec("countStep", .integer, defaultValue: .integer(0), unit: .count),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }
    public static let inspector = [
        InspectorSection(title: "Circle", controls: [.vector("centre"), .vector("axis"), .slider("radius"), .integer("count")]),
        InspectorSection(title: "Sweep", controls: [
            .slider("sweep"), .slider("startAngle"), .toggle("rotate", label: "Rotate with angle"),
        ]),
        InspectorSection(title: "Rings", controls: [.integer("rings"), .slider("radiusStep"), .integer("countStep")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let centre = try LayoutChecks.finite(try inputs.vector("centre"), "centre")
        let axis = try LayoutChecks.direction(try inputs.vector("axis"), "axis")
        let radius = try inputs.number("radius")
        let (sweep, start) = (try inputs.number("sweep"), try inputs.number("startAngle"))
        guard sweep.isFinite, start.isFinite, radius.isFinite else { throw NodeError.invalidValue("The circle's numbers must be finite.") }
        let (step, rotate) = (try LayoutChecks.finite(try inputs.number("radiusStep"), "radiusStep"), try inputs.bool("rotate"))
        let rings = try LayoutChecks.count(try inputs.integer("rings"), "rings")
        try PatternLimit.check(rings)
        let count = try LayoutChecks.count(try inputs.integer("count"), "count")
        let countStep = try inputs.integer("countStep")
        // Each ring's count is checked against the limit before it joins the total, so nothing is made for a pattern that's too big.
        var ringCounts: [Int] = []
        var total = 0
        for ring in 0..<rings {
            let (stepped, overflowed) = ring.multipliedReportingOverflow(by: countStep)
            let (ringCount, added) = count.addingReportingOverflow(stepped)
            guard !overflowed, !added else { throw PatternLimit.refusal }
            guard ringCount >= 0 else {
                throw NodeError.invalidValue("Ring \(ring) would have a negative count: raise “count” or lower “countStep”.")
            }
            try PatternLimit.check(ringCount)
            total += ringCount
            try PatternLimit.check(total)
            ringCounts.append(ringCount)
        }
        let around = FacePlane.plane(origin: centre, normal: axis).xAxis
        let across = axis.cross(around)
        let isFull = abs(sweep) >= 360 - 1e-9
        var branches: [DataTree] = []
        for (ring, ringCount) in ringCounts.enumerated() {
            let ringRadius = radius + Double(ring) * step
            guard ringRadius >= 0 else {
                throw NodeError.invalidValue("Ring \(ring) would have a negative radius: raise “radius” or lower “radiusStep”.")
            }
            let angleStep = isFull ? sweep / Double(max(ringCount, 1)) : (ringCount > 1 ? sweep / Double(ringCount - 1) : 0)
            let placements = (0..<ringCount).map { index -> Scalar in
                let angle = (start + angleStep * Double(index)) * .pi / 180
                let outwards = around * cos(angle) + across * sin(angle)
                return LayoutChecks.placement(centre + outwards * ringRadius, normal: axis, xAxis: rotate ? outwards : around)
            }
            branches.append(.list(placements))
        }
        return NodeOutputs(trees: ["placements": DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)])
    }
}
