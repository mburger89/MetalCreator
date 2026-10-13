import CreatorGeometry
import CreatorGraph

/// Where the slice quad lies and how far it covers (fields spec §6, "Slice plane"): a plane with the quad centred on the part's
/// box in it, an offset along the plane's normal that the viewport handle moves, and the limit of that offset. View state in
/// memory, never saved.
struct SlicePose: Equatable, Sendable {
    /// `.own` or `.axis` (a hidden slice has no pose).
    var choice: SliceChoice
    /// The plane at offset 0, its origin the part box's centre projected into it.
    var plane: Plane
    var offset: Double
    var halfWidth: Double
    var halfHeight: Double
    /// The most the offset may be in either direction: far enough to reach every corner of the box.
    var offsetLimit: Double

    /// The plane the quad lies in now.
    var worldPlane: Plane { plane.offset(by: offset) }

    /// How much of the box's size the quad covers beyond it.
    static let margin = 1.1

    /// How a preview of `field` starts: on the field's own plane when it has one, else on the axis plane nearest the view
    /// direction `toEye` (the axis whose normal is most nearly along it; ties XY, YZ, XZ).
    static func startingChoice(for field: Field, toEye: Vector3) -> SliceChoice {
        if let own = field.ownPlane, own.normal.normalized != nil { return .own }
        return .axis(SliceAxis.allCases.max { abs(toEye.dot($0.plane.normal)) < abs(toEye.dot($1.plane.normal)) } ?? .xy)
    }

    /// Where a preview of `field` starts for a part inside `bounds` seen from the direction `toEye`.
    static func starting(for field: Field, bounds: BoundingBox, toEye: Vector3) -> SlicePose {
        pose(for: startingChoice(for: field, toEye: toEye), field: field, bounds: bounds) ?? through(.xy, bounds: bounds)
    }

    /// The pose for a choice of place: on the field's own plane (`nil` if it has none), through the box's centre on an axis
    /// plane, or `nil` when hidden. Its offset is 0.
    static func pose(for choice: SliceChoice, field: Field, bounds: BoundingBox) -> SlicePose? {
        switch choice {
        case .own: field.ownPlane.map { fitted($0, choice: .own, bounds: bounds) }
        case .axis(let axis): through(axis, bounds: bounds)
        case .hidden: nil
        }
    }

    /// The axis plane through the box's centre.
    static func through(_ axis: SliceAxis, bounds: BoundingBox) -> SlicePose {
        var plane = axis.plane
        plane.origin = bounds.center
        return fitted(plane, choice: .axis(axis), bounds: bounds)
    }

    /// `plane` with the quad centred on the box in it and sized to cover the box's corners, with a margin.
    static func fitted(_ plane: Plane, choice: SliceChoice, bounds: BoundingBox) -> SlicePose {
        let (x, y, normal) = (plane.xAxis, plane.yAxis, plane.normal.normalized ?? plane.normal)
        let centre = bounds.center - plane.origin
        let origin = plane.origin + x * centre.dot(x) + y * centre.dot(y)
        let corners = [bounds.min.x, bounds.max.x].flatMap { cx in
            [bounds.min.y, bounds.max.y].flatMap { cy in [bounds.min.z, bounds.max.z].map { Vector3(cx, cy, $0) } }
        }
        func reach(_ axis: Vector3, from start: Vector3) -> Double { corners.map { abs(($0 - start).dot(axis)) }.max() ?? 0 }
        return SlicePose(choice: choice, plane: Plane(origin: origin, normal: normal, xAxis: x), offset: 0,
                         halfWidth: max(reach(x, from: origin) * margin, 0.5), halfHeight: max(reach(y, from: origin) * margin, 0.5),
                         offsetLimit: max(reach(normal, from: origin), 1))
    }

    /// The same pose at `offset` along the normal, held to the limit; a number that is not one leaves it where it is.
    func moved(to offset: Double) -> SlicePose {
        guard offset.isFinite else { return self }
        var moved = self
        moved.offset = min(max(offset, -offsetLimit), offsetLimit)
        return moved
    }

    /// The grid size (columns and rows) for `field`: 256, or 64 when sampling needs the kernel, since 65,536 kernel distances
    /// take seconds on OCCT (user decision 6; the spec says 256 throughout).
    static func resolution(for field: Field) -> Int {
        field.measuresWithKernel ? 64 : 256
    }
}
