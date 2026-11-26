import COCCT
import CreatorGeometry
import CreatorKernel

/// What the shim says about the pieces of a split solid: per piece, per face of the piece's own face map, where the face came from.
struct OCCTSplitSolidTables {
    struct Face {
        var sourceOperand: Int
        var sourceFace: Int
        var pairs: [(element: Int, side: Int)]
    }

    /// One list of faces per piece, in the order of the piece's own face map.
    var pieces: [[Face]]
    var dangling: Bool

    init(_ raw: occt_split_solid_result) {
        let pairs = UnsafeBufferPointer(start: raw.pairs, count: Int(raw.pair_count))
        var grouped = [[Face]](repeating: [], count: Int(raw.piece_count))
        for face in UnsafeBufferPointer(start: raw.faces, count: Int(raw.face_count)) {
            let range = Int(face.pair_start)..<(Int(face.pair_start) + Int(face.pair_count))
            grouped[Int(face.piece)].append(Face(sourceOperand: Int(face.source_operand), sourceFace: Int(face.source_face),
                                                 pairs: range.map { (Int(pairs[$0].element), Int(pairs[$0].side)) }))
        }
        pieces = grouped
        dangling = raw.dangling != 0
    }
}

extension OCCTShape {
    /// `solid` divided by `tools`; the shape is a compound of the pieces. Call under `OCCTKernel.serialized`.
    static func splitSolid(_ solid: OCCTShape, tools: [OCCTShape], cancel: OCCTCancelFlag)
        throws(OCCTError) -> (shape: OCCTShape, pieces: [OCCTShape], tables: OCCTSplitSolidTables) {
        var raw = occt_split_solid_result()
        defer { occt_split_solid_result_free(&raw) }
        let pointers: [OpaquePointer?] = tools.map(\.raw)
        let shape = try make { status in
            pointers.withUnsafeBufferPointer { buffer in
                occt_split_solid(solid.raw, buffer.baseAddress, Int32(buffer.count), cancel.raw, &raw, status)
            }
        }
        var pieces: [OCCTShape] = []
        for index in 0..<Int(occt_compound_child_count(shape.raw)) {
            pieces.append(try make { status in occt_compound_child(shape.raw, Int32(index), status) })
        }
        return (shape, pieces, OCCTSplitSolidTables(raw))
    }
}

extension OCCTKernel {
    static let danglingToolWarning = "Part of a tool doesn't cross the solid from side to side, so it cut nothing there."

    /// R13: `solid` divided by every face of `tools` (a sheet or a closed solid each). A piece's face keeps the tags of the face it came
    /// from plus a `cutSide` per tool face it borders or is made from; the pieces are ordered by `SheetPieces.ordered`.
    public func splitSolid(_ solid: Solid, by tools: [Solid], tag: NodeTag) async throws -> SolidSplit {
        try Task.checkCancellation()
        if let refusal = solid.splitSolidRefusal { throw KernelError.invalidInput(refusal) }
        let source = try shape(of: solid)
        guard !tools.isEmpty else { return SolidSplit(pieces: [solid], warnings: []) }
        let toolShapes = try tools.map { try shape(of: $0) }
        let flag = OCCTCancelFlag()
        let built: (shape: OCCTShape, pieces: [OCCTShape], tables: OCCTSplitSolidTables)
        do {
            built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, pieces: [OCCTShape], tables: OCCTSplitSolidTables) in
                    try OCCTShape.splitSolid(source, tools: toolShapes, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("split solid", error) }
            throw KernelError.invalidInput(error.message)
        }
        try Task.checkCancellation()
        // Element k is the k-th face over every tool's face map, in input order.
        let elementNames: [CutterName] = tools.flatMap { $0.topology.faces.map { CutterName.face($0.tags) } }
        let sides: [CutSide] = [.front, .back, .inside, .outside]
        let inputs = [solid.topology] + tools.map(\.topology)
        var pieces: [Solid] = []
        for (shape, faces) in zip(built.pieces, built.tables.pieces) {
            var history: [OCCTHistoryRecord] = []
            var faceTags: [Int: Set<TopoTag>] = [:]
            for (index, face) in faces.enumerated() {
                if face.sourceOperand >= 0, face.sourceFace > 0 {
                    history.append(OCCTHistoryRecord(outFace: index, kind: .face, operand: face.sourceOperand,
                                                     index: face.sourceFace - 1))
                }
                for pair in face.pairs where sides.indices.contains(pair.side) && elementNames.indices.contains(pair.element) {
                    faceTags[index, default: []].insert(TopoTag(tag, .cutSide(elementNames[pair.element], sides[pair.side])))
                }
            }
            pieces.append(try self.solid(from: shape, history: history, inputs: inputs, tag: tag, operation: "split solid",
                                         extraFaceTags: faceTags))
        }
        return SolidSplit(pieces: Self.orderedSolids(pieces),
                          warnings: built.tables.dangling ? [Self.danglingToolWarning] : [])
    }

    /// The pieces in `SheetPieces.ordered`'s order (their faces gathered into one topology to be ranked).
    static func orderedSolids(_ pieces: [Solid]) -> [Solid] {
        var faces: [FaceInfo] = []
        var groups: [[Int]] = []
        for piece in pieces {
            groups.append(Array(faces.count..<(faces.count + piece.topology.faces.count)))
            faces.append(contentsOf: piece.topology.faces)
        }
        let order = SheetPieces.ordered(groups: groups, in: Topology(faces: faces, edges: []))
        return order.compactMap { group in
            group.first.flatMap { first in groups.firstIndex { $0.first == first.rawValue }.map { pieces[$0] } }
        }
    }
}
