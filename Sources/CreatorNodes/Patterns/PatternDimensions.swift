import CreatorGeometry
import CreatorGraph

/// The dimensions the pattern features declare per placement (spec §3.1): sizes through `DimensionSpecs.repeated`, so
/// equal ones are one spec with a count and differing ones one spec each, up to the instance limit.
enum PatternDimensions {
    /// A diameter at each placement: a radial dimension of the circle round the origin, aimed along the placement's x axis.
    static func diameters(_ values: [Double], planes: [Plane]) -> [DimensionSpec] {
        DimensionSpecs.repeated(.input("diameter"), .diameter, values: values) { index in
            guard planes.indices.contains(index), values[index].isFinite else { return nil }
            let plane = planes[index]
            return .radial(center: plane.origin, radius: values[index] / 2, normal: plane.normal, toward: plane.xAxis, placement: .standoff)
        }
    }

    /// A depth cut into the part (against the normal) at each placement whose `through` is false.
    static func depths(_ values: [Double], through: [Bool], planes: [Plane]) -> [DimensionSpec] {
        let blind = values.indices.filter { planes.indices.contains($0) && through.indices.contains($0) && !through[$0] }
        return DimensionSpecs.repeated(.input("depth"), .length, values: blind.map { values[$0] }) { position in
            let plane = planes[blind[position]]
            return along(plane, -plane.normal, values[blind[position]], side: plane.xAxis)
        }
    }

    /// A height standing off each placement along its normal.
    static func heights(_ values: [Double], planes: [Plane]) -> [DimensionSpec] {
        DimensionSpecs.repeated(.input("height"), .length, values: values) { index in
            guard planes.indices.contains(index) else { return nil }
            return along(planes[index], planes[index].normal, values[index], side: planes[index].xAxis)
        }
    }

    /// A slot's length, end to end along the placement's x axis and centred on its origin.
    static func slotLengths(_ values: [Double], planes: [Plane]) -> [DimensionSpec] {
        DimensionSpecs.repeated(.input("length"), .length, values: values) { index in
            guard planes.indices.contains(index) else { return nil }
            return centred(planes[index], axis: planes[index].xAxis, values[index], side: planes[index].yAxis)
        }
    }

    /// A slot's width, across the placement's y axis and centred on its origin.
    static func slotWidths(_ values: [Double], planes: [Plane]) -> [DimensionSpec] {
        DimensionSpecs.repeated(.input("width"), .length, values: values) { index in
            guard planes.indices.contains(index) else { return nil }
            return centred(planes[index], axis: planes[index].yAxis, values[index], side: planes[index].xAxis)
        }
    }

    private static func along(_ plane: Plane, _ direction: Vector3, _ distance: Double, side: Vector3) -> DimensionGeometry? {
        guard distance.isFinite else { return nil }
        return .linear(from: plane.origin, to: plane.origin + direction * distance, direction: direction, side: side, placement: .standoff)
    }

    private static func centred(_ plane: Plane, axis: Vector3, _ extent: Double, side: Vector3) -> DimensionGeometry? {
        guard extent.isFinite else { return nil }
        return .linear(from: plane.origin - axis * (extent / 2), to: plane.origin + axis * (extent / 2), direction: axis, side: side,
                       placement: .standoff)
    }
}
