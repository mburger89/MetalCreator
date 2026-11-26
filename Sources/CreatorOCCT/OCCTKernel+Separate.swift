import COCCT
import CreatorKernel

/// What the shim says about the pieces of a separated value: per piece, whether it is a closed solid and, in the order of its own
/// face and edge maps, which face and edge of the input each one is.
struct OCCTSeparateTables {
    var isSolid: [Bool]
    var faces: [[Int]]
    var edges: [[Int]]

    init(_ raw: occt_separate_result) {
        let count = Int(raw.piece_count)
        isSolid = UnsafeBufferPointer(start: raw.kinds, count: count).map { $0 != 0 }
        var faces = [[Int]](repeating: [], count: count)
        var edges = [[Int]](repeating: [], count: count)
        let facePiece = UnsafeBufferPointer(start: raw.face_piece, count: Int(raw.face_count))
        let faceSource = UnsafeBufferPointer(start: raw.face_source, count: Int(raw.face_count))
        for (piece, source) in zip(facePiece, faceSource) { faces[Int(piece)].append(Int(source)) }
        let edgePiece = UnsafeBufferPointer(start: raw.edge_piece, count: Int(raw.edge_count))
        let edgeSource = UnsafeBufferPointer(start: raw.edge_source, count: Int(raw.edge_count))
        for (piece, source) in zip(edgePiece, edgeSource) { edges[Int(piece)].append(Int(source)) }
        self.faces = faces
        self.edges = edges
    }
}

extension OCCTShape {
    /// `value` taken apart; the shape is a compound of the pieces. Call under `OCCTKernel.serialized`.
    static func separate(_ value: OCCTShape) throws(OCCTError) -> (pieces: [OCCTShape], tables: OCCTSeparateTables) {
        var raw = occt_separate_result()
        defer { occt_separate_result_free(&raw) }
        let shape = try make { status in occt_separate(value.raw, &raw, status) }
        var pieces: [OCCTShape] = []
        for index in 0..<Int(occt_compound_child_count(shape.raw)) {
            pieces.append(try make { status in occt_compound_child(shape.raw, Int32(index), status) })
        }
        return (pieces, OCCTSeparateTables(raw))
    }
}

extension OCCTKernel {
    /// R3: the closed solids of `value` and its connected open pieces, in the shape's order, each keeping the tags of its faces and edges.
    public func separated(_ value: Solid, tag: NodeTag) async throws -> SeparatedBodies {
        try Task.checkCancellation()
        let source = try shape(of: value)
        let built: (pieces: [OCCTShape], tables: OCCTSeparateTables)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            built = try Self.serialized { () throws -> (pieces: [OCCTShape], tables: OCCTSeparateTables) in
                try OCCTShape.separate(source)
            }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("separate solids", error) }
            throw KernelError.invalidInput(error.message)
        }
        var result = SeparatedBodies(solids: [], sheets: [])
        for (index, piece) in built.pieces.enumerated() {
            let history = built.tables.faces[index].enumerated().map {
                OCCTHistoryRecord(outFace: $0.offset, kind: .face, operand: 0, index: $0.element - 1)
            }
            var overrides: [Int: Set<TopoTag>] = [:]
            for (edge, sourceEdge) in built.tables.edges[index].enumerated() where value.topology.edges.indices.contains(sourceEdge - 1) {
                overrides[edge] = value.topology.edges[sourceEdge - 1].tags
            }
            let body = try solid(from: piece, history: history, inputs: [value.topology], tag: tag, operation: "separate solids",
                                 edgeTagOverrides: overrides)
            if built.tables.isSolid[index] { result.solids.append(body) } else { result.sheets.append(body) }
        }
        return result
    }
}
