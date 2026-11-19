import COCCT
import CreatorGeometry
import CreatorKernel

/// What the shim says about a split sheet or a sub-sheet: where each face and edge of the result came from.
struct OCCTSplitTables {
    struct Face {
        var sourceFace: Int
        var piece: Int
        var inside: Int
        var pairs: [(element: Int, side: Int)]
    }

    struct Edge {
        var sourceEdge: Int
        var element: Int
    }

    var faces: [Face]
    var edges: [Edge]
    var pieceCount: Int
    var hasInside: Bool
    var dangling: Bool

    init(_ raw: occt_split_result) {
        let pairs = UnsafeBufferPointer(start: raw.pairs, count: Int(raw.pair_count))
        faces = UnsafeBufferPointer(start: raw.faces, count: Int(raw.face_count)).map { face in
            let range = Int(face.pair_start)..<(Int(face.pair_start) + Int(face.pair_count))
            return Face(sourceFace: Int(face.source_face), piece: Int(face.piece), inside: Int(face.inside),
                        pairs: range.map { (Int(pairs[$0].element), Int(pairs[$0].side)) })
        }
        edges = UnsafeBufferPointer(start: raw.edges, count: Int(raw.edge_count)).map {
            Edge(sourceEdge: Int($0.source_edge), element: Int($0.element))
        }
        pieceCount = Int(raw.piece_count)
        hasInside = raw.has_inside != 0
        dangling = raw.dangling != 0
    }
}

extension OCCTShape {
    /// `sheet` divided by a cutter (`kind` 0 along `direction`, 1 along normals, 2 the `body`). Call under `OCCTKernel.serialized`.
    static func splitSheet(_ sheet: OCCTShape, kind: Int32, curves: [OCCTShape], direction: Vector3, body: OCCTShape?,
                           cancel: OCCTCancelFlag) throws(OCCTError) -> (shape: OCCTShape, tables: OCCTSplitTables) {
        var raw = occt_split_result()
        defer { occt_split_result_free(&raw) }
        var vector = [direction.x, direction.y, direction.z]
        let pointers: [OpaquePointer?] = curves.map(\.raw)
        let shape = try make { status in
            pointers.withUnsafeBufferPointer { buffer in
                occt_split_sheet(sheet.raw, kind, buffer.baseAddress, Int32(buffer.count), &vector, body?.raw, cancel.raw, &raw, status)
            }
        }
        return (shape, OCCTSplitTables(raw))
    }

    /// The listed faces (0-based) of `sheet` as one sheet of the same shapes. Call under `OCCTKernel.serialized`.
    static func subSheet(of sheet: OCCTShape, faces: [Int]) throws(OCCTError) -> (shape: OCCTShape, tables: OCCTSplitTables) {
        var raw = occt_split_result()
        defer { occt_split_result_free(&raw) }
        let indices = faces.map { Int32($0 + 1) }
        let shape = try make { status in
            indices.withUnsafeBufferPointer { buffer in
                occt_sub_sheet(sheet.raw, buffer.baseAddress, Int32(buffer.count), &raw, status)
            }
        }
        return (shape, OCCTSplitTables(raw))
    }
}
