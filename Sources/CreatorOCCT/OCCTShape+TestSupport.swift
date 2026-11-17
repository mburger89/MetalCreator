import COCCT
import CreatorGeometry
import Foundation

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

    /// Writes the shape as an IGES file in `unit` ("MM", "IN"). Call under `OCCTKernel.serialized`.
    func writeIGES(to url: URL, unit: String = "MM") throws(OCCTError) {
        try Self.check { status in
            url.withUnsafeFileSystemRepresentation { path in unit.withCString { occt_test_write_iges(raw, path, $0, status) } }
        }
    }
}

extension OCCTShape {
    /// Writes the shape as a STEP file whose length unit is `unit` ("MM", "INCH"). Call under `OCCTKernel.serialized`.
    func writeSTEP(to url: URL, unit: String) throws(OCCTError) {
        try Self.check { status in
            url.withUnsafeFileSystemRepresentation { path in unit.withCString { occt_test_write_step_units(raw, path, $0, status) } }
        }
    }
}
