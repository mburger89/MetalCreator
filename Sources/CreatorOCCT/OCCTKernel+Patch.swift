import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

/// What the shim reports beside the face: how many pieces went in and which input piece is each loop piece.
struct PatchPieces: Sendable {
    var total = 0
    /// `order[k]` is the 0-based input index of the loop's piece k, numbered from input piece 0.
    var order: [Int] = []
}

/// What the shim is given: the curves, the part and the picked edges with the face each is held tangent to (1-based, 0 for none),
/// the points and interior curves.
struct PatchInputs {
    var curves: [OCCTShape]
    var part: OCCTShape?
    var edges: [Int32]
    var faces: [Int32]
    var points: [Vector3]
    var interior: [OCCTShape]
    var continuity: PatchContinuity
}

extension OCCTShape {
    /// The patch for `inputs`. Call under `OCCTKernel.serialized`.
    static func boundaryPatch(_ inputs: PatchInputs, cancel: OCCTCancelFlag, pieces: inout PatchPieces) throws(OCCTError) -> SheetBuild {
        let curvePointers: [OpaquePointer?] = inputs.curves.map(\.raw)
        let interiorPointers: [OpaquePointer?] = inputs.interior.map(\.raw)
        let flat = inputs.points.flatMap { [$0.x, $0.y, $0.z] }
        var order = [Int32](repeating: 0, count: 16)
        var total: Int32 = 0
        let partRaw = inputs.part?.raw
        let result = try buildingSheet { history, roles, status in
            curvePointers.withUnsafeBufferPointer { curveBuffer in
                interiorPointers.withUnsafeBufferPointer { interiorBuffer in
                    occt_boundary_patch(curveBuffer.baseAddress, Int32(curveBuffer.count), partRaw, inputs.edges, inputs.faces,
                                        Int32(inputs.edges.count), flat, Int32(inputs.points.count), interiorBuffer.baseAddress,
                                        Int32(interiorBuffer.count), Int32(inputs.continuity.rawValue), cancel.raw, &order,
                                        Int32(order.count), &total, history, roles, status)
                }
            }
        }
        pieces = PatchPieces(total: Int(total), order: order.prefix(Int(total)).map(Int.init))
        return result
    }
}

extension OCCTKernel {
    static let patchCannotHoldTangent = "The patch isn't tangent to the surface along piece %d; the hole may be too sharp for G1."
    static let patchOnlyG0 = "No bounding edge lies on a surface, so the patch is only G0."

    /// The shim's inputs for `boundary`, and which picked edges (by index) lie on a face of the part.
    private func patchInputs(_ boundary: PatchBoundary, points: [Vector3], interior: [Curve], continuity: PatchContinuity) throws
        -> (inputs: PatchInputs, supported: [Int]) {
        var edgeIndices: [Int32] = []
        var faceIndices: [Int32] = []
        var supported: [Int] = []
        if let part = boundary.part {
            for (index, edge) in boundary.edges.enumerated() {
                guard edge.rawValue >= 0, edge.rawValue < part.topology.edges.count else {
                    throw KernelError.invalidInput("That edge no longer exists.")
                }
                let info = part.topology.edges[edge.rawValue]
                edgeIndices.append(Int32(edge.rawValue + 1))
                let isFree = info.faces.count == 1 && !info.isSeam
                faceIndices.append(isFree ? Int32(info.faces[0].rawValue + 1) : 0)
                if isFree { supported.append(index) }
            }
        } else if !boundary.edges.isEmpty {
            throw KernelError.invalidInput("The picked edges need a part.")
        }
        let inputs = PatchInputs(curves: try boundary.curves.map { try curveShape(of: $0) },
                                 part: try boundary.part.map { try shape(of: $0) }, edges: edgeIndices, faces: faceIndices,
                                 points: points, interior: try interior.map { try curveShape(of: $0) }, continuity: continuity)
        return (inputs, supported)
    }

    public func boundaryPatch(_ boundary: PatchBoundary, interior points: [Vector3], interior curves: [Curve],
                              continuity: PatchContinuity, tag: NodeTag) async throws -> PatchResult {
        try Task.checkCancellation()
        guard continuity != .g2 else { throw KernelError.unsupported("G2 boundary patches") }
        guard points.allSatisfy(\.isFinite) else { throw KernelError.invalidInput("A point must be finite.") }
        let (inputs, supported) = try patchInputs(boundary, points: points, interior: curves, continuity: continuity)
        let flag = OCCTCancelFlag()
        var pieces = PatchPieces()
        let sheet: Solid
        do {
            sheet = try await withTaskCancellationHandler {
                try buildSheet("boundary patch", tag: tag) {
                    try OCCTShape.boundaryPatch(inputs, cancel: flag, pieces: &pieces)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch KernelError.invalidInput(let message) {
            if message == OCCTCancelFlag.message { throw CancellationError() }
            throw KernelError.invalidInput(Self.writingNumbers(in: message))
        }
        try Task.checkCancellation()
        guard continuity == .g1 else { return PatchResult(sheet: sheet) }
        guard let part = boundary.part, !supported.isEmpty else {
            return PatchResult(sheet: sheet, warnings: [Self.patchOnlyG0])
        }
        try await checkTangent(sheet, part: part, edges: boundary.edges, supported: supported, pieces: pieces, tag: tag)
        return PatchResult(sheet: sheet)
    }

    /// Holds each supported piece to G1 against its face, through the two-body call.
    private func checkTangent(_ sheet: Solid, part: Solid, edges: [EdgeID], supported: [Int], pieces: PatchPieces,
                              tag: NodeTag) async throws {
        let curveCount = pieces.total - edges.count
        for index in supported {
            let input = curveCount + index
            guard let loopPiece = pieces.order.firstIndex(of: input) else { continue }
            let role = TopoTag(tag, .boundary(.piece(loop: 0, segment: loopPiece)))
            guard let patchEdge = sheet.topology.edges.first(where: { $0.tags.contains(role) }),
                  let face = part.topology.edges[edges[index].rawValue].faces.first else { continue }
            let found = try await continuity(of: patchEdge.id, in: sheet, against: face, of: part)
            if found.grade < .g1 {
                throw KernelError.invalidInput(Self.patchCannotHoldTangent.replacingOccurrences(of: "%d", with: "\(input + 1)"))
            }
        }
    }
}
