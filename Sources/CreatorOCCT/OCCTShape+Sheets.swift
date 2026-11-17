import COCCT
import CreatorGeometry
import CreatorKernel

extension BoundaryRole {
    /// The shim's role table (`occt_boundary_roles`): one entry per edge of the shape in its edge map order, `nil` for kind 0.
    static func read(_ table: occt_boundary_roles) -> [BoundaryRole?] {
        UnsafeBufferPointer(start: table.roles, count: Int(table.count)).map { role in
            switch role.kind {
            case 1: .start
            case 2: .end
            case 3: .rail(Int(role.a))
            case 4: .piece(loop: Int(role.a), segment: Int(role.b))
            case 5: .imported(edge: Int(role.a))
            default: nil
            }
        }
    }
}

extension OCCTShape {
    /// Runs a shim sheet builder that returns a shape, a history and a boundary-role table (the contract Tasks 4, 5 and 8
    /// share); frees both. Call under `OCCTKernel.serialized`.
    static func buildingSheet(
        _ body: (UnsafeMutablePointer<occt_history>, UnsafeMutablePointer<occt_boundary_roles>, UnsafeMutablePointer<occt_status>)
            -> OpaquePointer?
    ) throws(OCCTError) -> (shape: OCCTShape, history: [OCCTHistoryRecord], roles: [BoundaryRole?]) {
        var history = occt_history()
        var roles = occt_boundary_roles()
        defer {
            occt_history_free(&history)
            occt_boundary_roles_free(&roles)
        }
        let shape = try make { status in body(&history, &roles, status) }
        return (shape, OCCTHistoryRecord.read(history), BoundaryRole.read(roles))
    }

    /// A face over closed `loops` (wires) lying in `plane`, looking along its normal. Call under `OCCTKernel.serialized`.
    static func planarSurface(loops: [OCCTShape], plane: Plane) throws(OCCTError)
        -> (shape: OCCTShape, history: [OCCTHistoryRecord], roles: [BoundaryRole?]) {
        var raw = occt_plane(origin: (plane.origin.x, plane.origin.y, plane.origin.z),
                             normal: (plane.normal.x, plane.normal.y, plane.normal.z),
                             x_axis: (plane.xAxis.x, plane.xAxis.y, plane.xAxis.z))
        let pointers: [OpaquePointer?] = loops.map(\.raw)
        return try buildingSheet { history, roles, status in
            pointers.withUnsafeBufferPointer { buffer in
                occt_planar_surface(buffer.baseAddress, Int32(buffer.count), &raw, history, roles, status)
            }
        }
    }
}
