import Foundation
import CreatorGeometry
import CreatorKernel

enum MeasureQuantity: Hashable, Sendable { case distance, angle, radius, diameter, length, area, centreDistance, position }

/// One number the Measure panel shows. Lengths in millimetres, angles in degrees.
struct MeasureReading: Hashable, Sendable {
    var quantity: MeasureQuantity
    var value: Double
    /// A corner's position (`value` is then 0).
    var point: Vector3?
}

/// What a pick is, geometrically, for angles and centre distances.
struct MeasureFeature {
    /// A straight edge's direction or a cylinder's axis (unit).
    var line: Vector3?
    /// A flat face's normal (unit).
    var normal: Vector3?
    /// A circle's centre, or a point on a cylinder's axis.
    var centre: Vector3?
    /// The axis of that circle or cylinder (unit).
    var axis: Vector3?
    var isCylinder = false

    static func of(_ pick: MeasurePick, _ topologies: [Int: Topology]) -> MeasureFeature {
        var feature = MeasureFeature()
        guard let topology = topologies[pick.solidIndex] else { return feature }
        switch pick {
        case let .face(_, id):
            guard let face = topology.face(id), let direction = face.normal?.normalized else { return feature }
            if face.kind == .plane {
                feature.normal = direction
            } else if face.kind == .cylinder, let point = face.axisPoint {
                feature.line = direction
                feature.axis = direction
                feature.centre = point
                feature.isCylinder = true
            }
        case let .edge(_, id):
            guard let edge = topology.edge(id) else { return feature }
            if case let .circle(center, axis, _, _, _)? = edge.curve {
                feature.centre = center
                feature.axis = axis.normalized
            } else if edge.kind == .line {
                feature.line = edge.direction?.normalized
            }
        case .corner:
            break
        }
        return feature
    }
}

enum MeasureReadings {
    /// Everything that needs no kernel call: one pick's readings, or two picks' angle and centre distance.
    static func readings(for picks: [MeasurePick], topologies: [Int: Topology]) -> [MeasureReading] {
        switch picks.count {
        case 1: single(picks[0], topologies)
        case 2: pair(picks[0], picks[1], topologies)
        default: []
        }
    }

    private static func single(_ pick: MeasurePick, _ topologies: [Int: Topology]) -> [MeasureReading] {
        switch pick {
        case let .corner(_, _, _, point):
            return [MeasureReading(quantity: .position, value: 0, point: point)]
        case let .face(solid, id):
            guard let face = topologies[solid]?.face(id) else { return [] }
            if face.kind == .cylinder, let radius = face.radius { return roundReadings(radius) }
            return [MeasureReading(quantity: .area, value: face.area)]
        case let .edge(solid, id):
            guard let edge = topologies[solid]?.edge(id) else { return [] }
            if case let .circle(_, _, radius, _, _)? = edge.curve { return roundReadings(radius) }
            return [MeasureReading(quantity: .length, value: edge.length)]
        }
    }

    private static func roundReadings(_ radius: Double) -> [MeasureReading] {
        [MeasureReading(quantity: .radius, value: radius), MeasureReading(quantity: .diameter, value: radius * 2)]
    }

    private static func pair(_ first: MeasurePick, _ second: MeasurePick, _ topologies: [Int: Topology]) -> [MeasureReading] {
        let a = MeasureFeature.of(first, topologies)
        let b = MeasureFeature.of(second, topologies)
        var made: [MeasureReading] = []
        if let degrees = angle(a, b) { made.append(MeasureReading(quantity: .angle, value: degrees)) }
        if let distance = centreDistance(a, b) { made.append(MeasureReading(quantity: .centreDistance, value: distance)) }
        return made
    }

    /// Between undirected lines and planes, 0° to 90°.
    static func angle(_ a: MeasureFeature, _ b: MeasureFeature) -> Double? {
        let degrees = 180 / Double.pi
        if let u = a.line, let v = b.line { return acos(min(1, abs(u.dot(v)))) * degrees }
        if let u = a.normal, let v = b.normal { return acos(min(1, abs(u.dot(v)))) * degrees }
        if let line = a.line ?? b.line, let normal = a.normal ?? b.normal { return asin(min(1, abs(line.dot(normal)))) * degrees }
        return nil
    }

    /// Between two circles' centres, or from a circle's centre to a cylinder's axis, or between two axes; not for axes that
    /// are not parallel within 1e-6 rad.
    static func centreDistance(_ a: MeasureFeature, _ b: MeasureFeature) -> Double? {
        guard let p = a.centre, let q = b.centre, let u = a.axis, let v = b.axis, u.cross(v).length < 1e-6 else { return nil }
        let offset = q - p
        if !a.isCylinder && !b.isCylinder { return offset.length }
        let axis = a.isCylinder ? u : v
        return (offset - axis * offset.dot(axis)).length
    }
}
