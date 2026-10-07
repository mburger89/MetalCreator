import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    static func boolean(_ op: BooleanOp, _ a: OCCTShape, _ tools: [OCCTShape]) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let code: Int32 = switch op {
        case .union: 0
        case .subtract: 1
        case .intersect: 2
        }
        let pointers: [OpaquePointer?] = tools.map(\.raw)
        return try pointers.withUnsafeBufferPointer { buffer throws(OCCTError) in
            try building { history, status in
                occt_boolean(code, a.raw, buffer.baseAddress, Int32(buffer.count), history, status)
            }
        }
    }

    func transformed(by transform: Transform) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let translation = [transform.translation.x, transform.translation.y, transform.translation.z]
        let axis = transform.rotationAxis ?? Axis.z
        let origin = [axis.origin.x, axis.origin.y, axis.origin.z]
        let direction = [axis.direction.x, axis.direction.y, axis.direction.z]
        let hasRotation: Int32 = transform.rotationAxis != nil && transform.rotation.radians != 0 ? 1 : 0
        return try Self.building { history, status in
            occt_transform(raw, translation, hasRotation, origin, direction, transform.rotation.radians, history, status)
        }
    }
}
