import COCCT
import CreatorKernel

/// What the shim says about a capped sheet.
struct OCCTCapTables {
    var history: [OCCTHistoryRecord]
    var edges: [OCCTEdgeHistoryRecord]
    /// Per cap face (0-based in the result), the input edges of its outer loop (0-based).
    var capEdges: [Int: [Int]]
    var capped: Int
    var notFlat: Int
}

extension OCCTShape {
    /// `self`'s flat holes capped. Call under `OCCTKernel.serialized`.
    func capPlanarHoles(flatness: Double, cancel: OCCTCancelFlag)
        throws(OCCTError) -> (shape: OCCTShape, tables: OCCTCapTables) {
        var history = occt_history()
        var edges = occt_edge_history()
        var loops = occt_cap_loops()
        defer {
            occt_history_free(&history)
            occt_edge_history_free(&edges)
            occt_cap_loops_free(&loops)
        }
        var capped: Int32 = 0
        var notFlat: Int32 = 0
        let shape = try Self.make { status in
            occt_cap_planar_holes(self.raw, flatness, cancel.raw, &history, &edges, &loops, &capped, &notFlat, status)
        }
        var capEdges: [Int: [Int]] = [:]
        for record in UnsafeBufferPointer(start: loops.records, count: Int(loops.count)) {
            capEdges[Int(record.face) - 1, default: []].append(Int(record.edge) - 1)
        }
        let tables = OCCTCapTables(history: OCCTHistoryRecord.read(history), edges: OCCTEdgeHistoryRecord.read(edges),
                                   capEdges: capEdges, capped: Int(capped), notFlat: Int(notFlat))
        return (shape, tables)
    }
}

extension OCCTKernel {
    /// R12: every flat closed free loop of `sheet` is capped (loops in one plane nested into faces with holes), the caps are sewn on and
    /// each closed shell becomes a solid; a cap is `.blend(sourceEdge:)` of the edge with the smallest key among its outer loop's edges.
    public func cappingPlanarHoles(_ sheet: Solid, tag: NodeTag) async throws -> CapResult {
        try Task.checkCancellation()
        let source = try shape(of: sheet)
        let flag = OCCTCancelFlag()
        let built: (shape: OCCTShape, tables: OCCTCapTables)
        do {
            built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, tables: OCCTCapTables) in
                    try source.capPlanarHoles(flatness: Self.capFlatness, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("cap planar holes", error) }
            throw KernelError.invalidInput(error.message)
        }
        try Task.checkCancellation()
        var history = built.tables.history
        for (face, edges) in built.tables.capEdges.sorted(by: { $0.key < $1.key }) {
            let keyed = edges.compactMap { index -> (String, Int)? in
                guard let edge = sheet.topology.edge(EdgeID(index)), let key = sheet.topology.key(of: edge) else { return nil }
                return (key.sortKey, index)
            }
            guard let smallest = keyed.min(by: { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }) else { continue }
            history.append(OCCTHistoryRecord(outFace: face, kind: .edge, operand: 0, index: smallest.1))
        }
        let body = try solid(from: built.shape, history: history, inputs: [sheet.topology], tag: tag,
                             operation: "cap planar holes", edgeHistory: built.tables.edges)
        return CapResult(body: body, capped: built.tables.capped, notFlat: built.tables.notFlat)
    }

    /// R12's fixed flatness: every sample of a loop within this many millimetres of its least-squares plane.
    static let capFlatness = 0.01
}
