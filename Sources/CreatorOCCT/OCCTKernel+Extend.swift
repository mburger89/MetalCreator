import COCCT
import CreatorGeometry
import CreatorKernel

/// Extending a sheet's one face across its free edges (NURBS spec NS-4, R8).
extension OCCTShape {
    /// The shape with face `faceIndex` (0-based) grown across the sides of `edges` (0-based). Call under `OCCTKernel.serialized`.
    func extendingFace(_ faceIndex: Int, edges: [Int], length: Double, mode: ExtendMode) throws(OCCTError) -> OCCTShape {
        let indices = edges.map { Int32(clamping: $0 + 1) }
        return try Self.make { status in
            indices.withUnsafeBufferPointer { buffer in
                occt_extend_face(self.raw, Int32(faceIndex + 1), buffer.baseAddress, Int32(buffer.count), length,
                                 Int32(mode.rawValue), status)
            }
        }
    }
}

extension OCCTKernel {
    public func extended(_ sheet: Solid, edges: [EdgeID], length: Double, mode: ExtendMode) async throws -> Solid {
        try Task.checkCancellation()
        guard sheet.hasOpenShell else { throw KernelError.invalidInput("Extend Surface takes a sheet; this is a closed solid.") }
        let faceCount = sheet.topology.faces.count
        guard faceCount == 1 else {
            throw KernelError.invalidInput(
                "Extend Surface takes a sheet with one face; this one has \(faceCount.formatted(.number.locale(.messages))).")
        }
        guard length.isFinite, length > 0 else { throw KernelError.invalidInput("The length must be greater than 0 mm.") }
        guard !edges.isEmpty, edges.allSatisfy({ (0..<sheet.topology.edges.count).contains($0.rawValue) }) else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        let source = try shape(of: sheet)
        let indices = edges.map(\.rawValue)
        let grown = try controlNetCall("extend surface") {
            try source.extendingFace(0, edges: indices, length: length, mode: mode)
        }
        try Task.checkCancellation()
        return try carryingTopology(of: grown, from: sheet, source: source, operation: "extend surface")
    }
}
