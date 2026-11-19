import COCCT
import CreatorGeometry
import CreatorKernel
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

extension OCCTShape {
    /// FOR TESTS ONLY. The one-face sheet with its apex row's poles moved `distance` apart. Call under `OCCTKernel.serialized`.
    func spreadingApex(by distance: Double) throws(OCCTError) -> OCCTShape {
        try Self.make { status in occt_test_spread_apex(raw, distance, status) }
    }

    /// FOR TESTS ONLY. A periodic tube of one face over `fraction` of its period. Call under `OCCTKernel.serialized`.
    static func partialPeriodicSheet(fraction: Double) throws(OCCTError) -> OCCTShape {
        try make { status in occt_test_partial_periodic_sheet(fraction, status) }
    }
}

extension OCCTKernel {
    /// FOR TESTS ONLY. `sheet` with its apex row's poles moved `distance` apart, bypassing the guard; tags and names kept.
    func spreadingApex(of sheet: Solid, by distance: Double) throws -> Solid {
        let source = try shape(of: sheet)
        let spread = try controlNetCall("spread apex") { try source.spreadingApex(by: distance) }
        return try carryingTopology(of: spread, from: sheet, source: source, operation: "spread apex")
    }

    /// FOR TESTS ONLY. A one-face periodic tube over `fraction` of its period.
    func partialPeriodicSheet(fraction: Double, tag: NodeTag) throws -> Solid {
        let shape: OCCTShape
        do {
            shape = try Self.serialized { () throws -> OCCTShape in try OCCTShape.partialPeriodicSheet(fraction: fraction) }
        } catch let error as OCCTError {
            throw KernelError.occt("test sheet", error)
        }
        return try solid(from: shape, history: [], inputs: [], tag: tag, operation: "test sheet")
    }
}
