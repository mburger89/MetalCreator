import COCCT
import CreatorKernel

/// What the shim says about a sewn shape.
struct OCCTSewTables {
    var history: [OCCTHistoryRecord]
    var edges: [OCCTEdgeHistoryRecord]
    var solids: Int
    var sheets: Int
    var unclosable: Int
}

extension OCCTShape {
    /// The faces of `bodies` sewn at `tolerance`. Call under `OCCTKernel.serialized`.
    static func sew(_ bodies: [OCCTShape], tolerance: Double, cancel: OCCTCancelFlag)
        throws(OCCTError) -> (shape: OCCTShape, tables: OCCTSewTables) {
        var history = occt_history()
        var edges = occt_edge_history()
        defer {
            occt_history_free(&history)
            occt_edge_history_free(&edges)
        }
        var solids: Int32 = 0
        var sheets: Int32 = 0
        var unclosable: Int32 = 0
        let pointers: [OpaquePointer?] = bodies.map(\.raw)
        let shape = try make { status in
            pointers.withUnsafeBufferPointer { buffer in
                occt_sew(buffer.baseAddress, Int32(buffer.count), tolerance, cancel.raw, &history, &edges,
                         &solids, &sheets, &unclosable, status)
            }
        }
        let tables = OCCTSewTables(history: OCCTHistoryRecord.read(history), edges: OCCTEdgeHistoryRecord.read(edges),
                                   solids: Int(solids), sheets: Int(sheets), unclosable: Int(unclosable))
        return (shape, tables)
    }
}

extension OCCTKernel {
    /// R6: every face of every body is sewn at `tolerance`; each closed shell becomes a solid, the rest stay sheets.
    public func sewn(_ bodies: [Solid], tolerance: Double, tag: NodeTag) async throws -> SewResult {
        try Task.checkCancellation()
        guard !bodies.isEmpty else { throw KernelError.invalidInput("Sew needs at least one surface.") }
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The tolerance must be greater than 0.")
        }
        let shapes = try bodies.map { try shape(of: $0) }
        let flag = OCCTCancelFlag()
        let built: (shape: OCCTShape, tables: OCCTSewTables)
        do {
            built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, tables: OCCTSewTables) in
                    try OCCTShape.sew(shapes, tolerance: tolerance, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("sew", error) }
            throw KernelError.invalidInput(error.message)
        }
        try Task.checkCancellation()
        let body = try solid(from: built.shape, history: built.tables.history, inputs: bodies.map(\.topology), tag: tag,
                             operation: "sew", edgeHistory: built.tables.edges)
        return SewResult(body: body, solids: built.tables.solids, sheets: built.tables.sheets,
                         unclosable: built.tables.unclosable)
    }
}
