import CreatorGeometry
import CreatorKernel
import CreatorViewport

enum MeasureDimensions {
    /// The dimensions the viewport draws for a measurement: the distance, one pick's radius, diameter or length, and the
    /// angle at the middle of the distance's witness segment. Tinted as references, ids `measure/<n>`.
    static func dimensions(for picks: [MeasurePick], readings: [MeasureReading], distance: ShapeDistance?,
                           topologies: [Int: Topology], style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension] {
        var shapes: [(DimensionGeometry, DimensionReading)] = []
        if let distance, distance.distance > 1e-9 {
            shapes.append((linear(from: distance.from, to: distance.to), DimensionReading(distance.distance, .length)))
        }
        if picks.count == 1 { shapes += single(picks[0], topologies) }
        if picks.count == 2, let distance, let angle = readings.first(where: { $0.quantity == .angle }),
           let geometry = angular(picks[0], picks[1], at: (distance.from + distance.to) * 0.5, topologies) {
            shapes.append((geometry, DimensionReading(angle.value, .angle)))
        }
        return shapes.enumerated().map { index, shape in
            OverlayDimension(id: OverlayDimensionID("measure/\(index)"), geometry: shape.0,
                             text: style.text(shape.1, units: units), tint: .dimensionReference)
        }
    }

    private static func linear(from: Vector3, to: Vector3) -> DimensionGeometry {
        let direction = (to - from).normalized ?? .unitX
        return .linear(from: from, to: to, direction: direction, side: perpendicular(to: direction), placement: .standoff)
    }

    /// A unit vector across `direction`, found against the world axis it leans on least.
    static func perpendicular(to direction: Vector3) -> Vector3 {
        let axes = [Vector3.unitZ, .unitY, .unitX]
        let axis = axes.min { abs($0.dot(direction)) < abs($1.dot(direction)) } ?? .unitZ
        let side = axis.cross(direction).cross(direction) * -1
        return side.normalized ?? .unitY
    }

    private static func single(_ pick: MeasurePick, _ topologies: [Int: Topology]) -> [(DimensionGeometry, DimensionReading)] {
        switch pick {
        case let .edge(solid, id):
            guard let edge = topologies[solid]?.edge(id) else { return [] }
            switch edge.curve {
            case let .circle(center, axis, radius, start, sweep)?:
                return [circle(center: center, axis: axis, radius: radius, start: start, sweep: sweep)]
            case let .line(start, end)?:
                return [(linear(from: start, to: end), DimensionReading(edge.length, .length))]
            case nil:
                return []
            }
        case let .face(solid, id):
            guard let face = topologies[solid]?.face(id), face.kind == .cylinder, let radius = face.radius,
                  let axisPoint = face.axisPoint, let axis = face.normal?.normalized else { return [] }
            let centre = axisPoint + axis * (face.centroid - axisPoint).dot(axis)
            let out = face.centroid - centre
            let toward = (out - axis * out.dot(axis)).normalized ?? perpendicular(to: axis)
            return [(.radial(center: centre, radius: radius, normal: axis, toward: toward, placement: .standoff),
                     DimensionReading(radius * 2, .diameter)),
            ]
        case .corner:
            return []
        }
    }

    private static func circle(center: Vector3, axis: Vector3, radius: Double, start: Vector3,
                               sweep: Double) -> (DimensionGeometry, DimensionReading) {
        let isFull = sweep >= 2 * Double.pi - 1e-9
        let normal = axis.normalized ?? .unitZ
        let middle = MeasureSnap.rotate(start, about: center, axis: normal, by: isFull ? 0 : sweep / 2)
        let toward = (middle - center).normalized ?? perpendicular(to: normal)
        let geometry = DimensionGeometry.radial(center: center, radius: radius, normal: normal, toward: toward, placement: .standoff)
        return (geometry, isFull ? DimensionReading(radius * 2, .diameter) : DimensionReading(radius, .radius))
    }

    /// The angle between two lines or planes at `vertex`, with arms in the plane they span; `nil` when parallel.
    private static func angular(_ first: MeasurePick, _ second: MeasurePick, at vertex: Vector3,
                                _ topologies: [Int: Topology]) -> DimensionGeometry? {
        let a = MeasureFeature.of(first, topologies)
        let b = MeasureFeature.of(second, topologies)
        guard let (u, v) = arms(a, b), let normal = u.cross(v).normalized else { return nil }
        return .angular(vertex: vertex, first: vertex + u, second: vertex + v, normal: normal, placement: .standoff)
    }

    /// Two unit arms with a non-negative dot, or `nil` when the angle is 0.
    private static func arms(_ a: MeasureFeature, _ b: MeasureFeature) -> (Vector3, Vector3)? {
        var pair: (Vector3, Vector3)?
        if let u = a.line, let v = b.line {
            pair = (u, v)
        } else if let u = a.normal, let v = b.normal {
            pair = (u, v)
        } else if let line = a.line ?? b.line, let normal = a.normal ?? b.normal,
                  let flat = (line - normal * line.dot(normal)).normalized {
            pair = (line, flat)
        }
        guard var (u, v) = pair else { return nil }
        if u.dot(v) < 0 { v = -v }
        guard u.cross(v).length > 1e-9 else { return nil }
        return (u, v)
    }
}
