import CreatorGeometry

extension FakeKernel {
    /// The frame of a planar face: its centroid, outward normal, and the axes (u along world X projected onto the face, or world Y when
    /// X is nearly along the normal; v completes a right-handed frame). The Fake has no curved faces.
    static func planarFrame(of id: FaceID, in solid: Solid) throws -> (origin: Vector3, normal: Vector3, xAxis: Vector3, yAxis: Vector3) {
        guard let face = solid.topology.face(id) else {
            throw KernelError.invalidInput("The face doesn't exist on the solid.")
        }
        guard face.kind == .plane, let normal = face.normal?.normalized else {
            throw KernelError.unsupported("face mapping on a curved face")
        }
        func inPlane(_ axis: Vector3) -> Vector3 { axis - normal * axis.dot(normal) }
        let projected = inPlane(.unitX)
        let xAxis = (projected.length >= 1e-3 ? projected : inPlane(.unitY)).normalized ?? .unitX
        return (face.centroid, normal, xAxis, normal.cross(xAxis))
    }
}
