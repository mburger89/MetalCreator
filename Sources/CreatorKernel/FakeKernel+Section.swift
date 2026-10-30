import CreatorGeometry

extension FakeKernel {
    /// A test knob: runs at the start of every `section`, on the kernel's thread; it may throw to refuse the section or block to
    /// hold it. `nil` (the default) does nothing.
    public func setSectionHook(_ hook: (@Sendable () throws -> Void)?) {
        sectionHook = hook
    }

    /// Sections the solid's bounding box by an axis-aligned plane; any other plane is refused.
    static func section(_ solid: Solid, by plane: Plane, tolerance: Double) throws -> PlaneSection {
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The section tolerance must be a positive number.")
        }
        guard let normal = plane.normal.normalized else {
            throw KernelError.invalidInput("The section plane has no direction.")
        }
        let components = [normal.x, normal.y, normal.z]
        guard let axis = components.firstIndex(where: { abs(abs($0) - 1) <= 1e-9 }) else {
            throw KernelError.unsupported("section on a tilted plane")
        }
        func value(_ vector: Vector3, _ index: Int) -> Double { [vector.x, vector.y, vector.z][index] }
        func point(_ index: Int, _ along: Int, _ across: Int, _ height: Double, _ u: Double, _ v: Double) -> Vector3 {
            var parts = [0.0, 0.0, 0.0]
            parts[index] = height
            parts[along] = u
            parts[across] = v
            return Vector3(parts[0], parts[1], parts[2])
        }
        let height = value(plane.origin, axis)
        let low = value(solid.bounds.min, axis), high = value(solid.bounds.max, axis)
        guard height > low, height < high else { return PlaneSection() }
        let (a, b) = ((axis + 1) % 3, (axis + 2) % 3)
        let (a0, a1) = (value(solid.bounds.min, a), value(solid.bounds.max, a))
        let (b0, b1) = (value(solid.bounds.min, b), value(solid.bounds.max, b))
        let corners = [point(axis, a, b, height, a0, b0), point(axis, a, b, height, a1, b0),
                       point(axis, a, b, height, a1, b1), point(axis, a, b, height, a0, b1),
        ]
        // Each side's outward direction: -a, +b, +a, -b for the corner order above.
        func outward(_ index: Int, _ sign: Double) -> Vector3 { point(0, index, index, 0, sign, sign) }
        let sides: [Vector3] = [outward(b, -1), outward(a, 1), outward(b, 1), outward(a, -1)]
        let pieces = (0..<4).map { index -> SectionPiece in
            let (start, end) = (corners[index], corners[(index + 1) % 4])
            let face = solid.topology.faces.first { face in
                guard face.kind == .plane, let faceNormal = face.normal?.normalized else { return false }
                return faceNormal.dot(sides[index]) > 1 - 1e-9
            }
            return SectionPiece(curve: .line(start: start, end: end), polyline: [start, end], sourceFace: face?.id)
        }
        return PlaneSection(regions: [SectionRegion(positions: corners, triangles: [0, 1, 2, 0, 2, 3], boundary: pieces)])
    }
}
