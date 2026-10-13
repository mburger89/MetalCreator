import COCCT
import CreatorGeometry

/// Wrappers for the shim's test-only helpers (`occt_test_*`). Nothing in the app calls them.
extension OCCTShape {
    /// A copy carrying a non-identity `TopLoc_Location` (a rotation about Z, then a translation), as a STEP import can give.
    /// Call under `OCCTKernel.serialized`.
    func locatedCopy(translation: Vector3, rotationAboutZ angle: Double) throws(OCCTError) -> OCCTShape {
        let offset = [translation.x, translation.y, translation.z]
        return try Self.make { status in
            offset.withUnsafeBufferPointer { occt_test_located_copy(raw, $0.baseAddress, angle, status) }
        }
    }

    /// The largest vertex tolerance in millimetres (the default for a fresh vertex is 1e-7).
    var largestVertexTolerance: Double { occt_test_max_vertex_tolerance(raw) }
}
