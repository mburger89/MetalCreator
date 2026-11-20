import COCCT
import CreatorKernel
import Foundation

extension OCCTShape {
    /// FOR TESTS ONLY. A copy sharing no geometry or topology with this shape. Call under `OCCTKernel.serialized`.
    func independentCopy() throws(OCCTError) -> OCCTShape {
        try Self.make { status in occt_test_independent_copy(raw, status) }
    }
}

extension OCCTKernel {
    /// FOR TESTS ONLY. A box's six loose faces, the top moved `movingTopBy` mm, held as one unchecked solid whose shell has gaps.
    func gappedBoxSolid(size: Double = 10, movingTopBy: Double, tag: NodeTag) throws -> Solid {
        let shape: OCCTShape
        do {
            shape = try Self.serialized { () throws -> OCCTShape in
                try OCCTShape.make { status in occt_test_loose_box_faces(size, movingTopBy, 0, 1, status) }
            }
        } catch let error as OCCTError {
            throw KernelError.occt("test solid", error)
        }
        return try solid(from: shape, history: [], inputs: [], tag: tag, operation: "test solid")
    }

    /// FOR TESTS ONLY (R19). A `size` mm box's six faces, each copied on its own so none shares an edge with another, the top face
    /// moved `movingTopBy` mm outward and, with `doublingTop`, written a second time last, as STEP bytes.
    static func looseBoxFaces(size: Double = 10, movingTopBy: Double = 0, doublingTop: Bool = false) throws -> Data {
        let directory = URL.temporaryDirectory.appending(path: "loose-box-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "faces.step")
        try serialized { () throws in
            let faces = try OCCTShape.make { status in
                occt_test_loose_box_faces(size, movingTopBy, doublingTop ? 1 : 0, 0, status)
            }
            try faces.writeSTEP(to: url, unit: "MM")
        }
        return try Data(contentsOf: url)
    }
}
