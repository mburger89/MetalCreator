import COCCT
import CreatorGeometry
import CreatorKernel

/// What the shim says about an offset shell.
struct OCCTOffsetTables {
    var history: [OCCTHistoryRecord]
    var edges: [OCCTEdgeHistoryRecord]
}

extension OCCTShape {
    /// `self` offset by `distance`. Call under `OCCTKernel.serialized`.
    func offsetSurface(distance: Double, cancel: OCCTCancelFlag) throws(OCCTError) -> (shape: OCCTShape, tables: OCCTOffsetTables) {
        var history = occt_history()
        var edges = occt_edge_history()
        defer {
            occt_history_free(&history)
            occt_edge_history_free(&edges)
        }
        let shape = try Self.make { status in occt_offset_surface(self.raw, distance, cancel.raw, &history, &edges, status) }
        return (shape, OCCTOffsetTables(history: OCCTHistoryRecord.read(history), edges: OCCTEdgeHistoryRecord.read(edges)))
    }

    /// The smallest positive distance along (`sign` 1) or against (-1) the normals that reaches a centre of curvature. Call under `OCCTKernel.serialized`.
    func offsetLimit(sign: Int) throws(OCCTError) -> Double {
        var limit = 0.0
        try Self.check { status in occt_offset_limit(self.raw, Int32(sign), &limit, status) }
        return limit
    }

    /// Whether two different pieces have edges sewing would join (R11). Call under `OCCTKernel.serialized`.
    func touchingPieces() throws(OCCTError) -> Bool {
        var touching: Int32 = 0
        try Self.check { status in occt_touching_pieces(self.raw, &touching, status) }
        return touching != 0
    }

    /// FOR TESTS ONLY. See `occt_test_wrapped_sheet`. Call under `OCCTKernel.serialized`.
    static func wrappedSheet(radius: Double, height: Double) throws(OCCTError) -> OCCTShape {
        try make { status in occt_test_wrapped_sheet(radius, height, status) }
    }
}

extension OCCTKernel {
    static let foldedSentence = "The surface folds over itself, so it can't be offset; move its control points apart first."
    static let touchingSentence = "Parts of the surface touch but aren't joined; Sew them first."
    static let openEdgesSentence = "The offset changed the surface's open edges, so it can't be offset."

    /// How one try at an offset distance ended.
    enum OffsetTry {
        case built(OCCTShape, OCCTOffsetTables)
        case failed(reason: String?)
    }

    /// R4, R7 to R9, R11: `sheet` offset along its normals by `distance`. Each face is its source's tags plus `.endCap`, each boundary
    /// edge keeps its paired source edge's tags.
    public func offsetSurface(_ sheet: Solid, distance: Double, tag: NodeTag) async throws -> Solid {
        try Task.checkCancellation()
        guard distance.isFinite, distance != 0 else { throw KernelError.invalidInput("The distance can't be 0.") }
        guard sheet.hasOpenShell else { throw KernelError.invalidInput("Offset Surface takes a sheet; this is a closed solid.") }
        guard !sheet.holdsClosedSolid else {
            throw KernelError.invalidInput("Offset Surface takes sheets only; this value also holds a closed solid.")
        }
        guard try !folds(sheet) else { throw KernelError.invalidInput(Self.foldedSentence) }
        let source = try shape(of: sheet)
        let touching = try controlNetCall("offset surface") { try source.touchingPieces() }
        guard !touching else { throw KernelError.invalidInput(Self.touchingSentence) }
        let sign = distance < 0 ? -1 : 1
        let limit = try controlNetCall("offset surface") { try source.offsetLimit(sign: sign) }

        // R8: a distance counts when it builds and stays short of the curvature limit.
        let first = try await offsetAttempt(source, distance: distance, limit: limit)
        if case .built(let shape, let tables) = first {
            return try offsetSolid(shape, tables, of: sheet, tag: tag)
        }
        var firstReason: String?
        if case .failed(let reason) = first { firstReason = reason }
        let largest = try await largestValidOffset(below: abs(distance), limit: limit) { magnitude in
            if case .built = try await self.offsetAttempt(source, distance: Double(sign) * magnitude, limit: limit) { return true }
            return false
        }
        if largest == nil, let firstReason { throw KernelError.invalidInput(firstReason) }
        throw KernelError.offsetFailed(distance: distance, largest: largest)
    }

    /// One build at `distance`, held to R8's curvature rule; a refusal of the shim is a failed try, a cancellation is thrown.
    func offsetAttempt(_ source: OCCTShape, distance: Double, limit: Double) async throws -> OffsetTry {
        try Task.checkCancellation()
        guard abs(distance) < limit else { return .failed(reason: nil) }
        let flag = OCCTCancelFlag()
        do {
            let built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, tables: OCCTOffsetTables) in
                    try source.offsetSurface(distance: distance, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
            try Task.checkCancellation()
            return .built(built.shape, built.tables)
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            return .failed(reason: error.message == Self.openEdgesSentence ? error.message : nil)
        }
    }

    func offsetSolid(_ shape: OCCTShape, _ tables: OCCTOffsetTables, of sheet: Solid, tag: NodeTag) throws -> Solid {
        let end = TopoTag(tag, .endCap)
        let faceCount = Set(tables.history.map(\.outFace))
        var extra: [Int: Set<TopoTag>] = [:]
        for face in faceCount { extra[face] = [end] }
        return try solid(from: shape, history: tables.history, inputs: [sheet.topology], tag: tag, operation: "offset surface",
                         extraFaceTags: extra, edgeHistory: tables.edges)
    }

    /// The largest magnitude below `size` and `limit`, on a 0.01 mm grid, that `build` accepts; nil when not even 0.01 mm does. It
    /// bisects (at most 20 builds), assuming every magnitude above one that fails fails too, and a cancelled evaluation stops
    /// between builds (R8).
    func largestValidOffset(below size: Double, limit: Double,
                            build: (Double) async throws -> Bool) async throws -> Double? {
        var works = 0
        var fails = KernelError.OffsetGrid.firstFailing(for: min(size, limit))
        var builds = 0
        while fails - works > 1, builds < 20 {
            try Task.checkCancellation()
            let hundredths = (works + fails) / 2
            builds += 1
            if try await build(Double(hundredths) / 100) { works = hundredths } else { fails = hundredths }
        }
        try Task.checkCancellation()
        return works > 0 ? Double(works) / 100 : nil
    }

    /// FOR TESTS ONLY. Whether two different pieces of `sheet` touch (R11).
    func touchesItself(_ sheet: Solid) throws -> Bool {
        let shape = try shape(of: sheet)
        return try controlNetCall("touching pieces") { try shape.touchingPieces() }
    }

    /// FOR TESTS ONLY. R8's curvature limit of `sheet` on the `sign` side.
    func curvatureLimit(of sheet: Solid, sign: Int) throws -> Double {
        let shape = try shape(of: sheet)
        return try controlNetCall("offset limit") { try shape.offsetLimit(sign: sign) }
    }

    /// FOR TESTS ONLY. A one-face sheet wrapped round a circle with its two side edges lying on each other.
    func wrappedSheet(radius: Double, height: Double, tag: NodeTag) throws -> Solid {
        let shape: OCCTShape
        do {
            shape = try Self.serialized { () throws -> OCCTShape in try OCCTShape.wrappedSheet(radius: radius, height: height) }
        } catch let error as OCCTError {
            throw KernelError.occt("test sheet", error)
        }
        return try solid(from: shape, history: [], inputs: [], tag: tag, operation: "test sheet")
    }
}
