import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    /// `self` thickened by `distance` on `side` (0 front, 1 back, 2 both). Call under `OCCTKernel.serialized`.
    func thicken(distance: Double, side: Int,
                 cancel: OCCTCancelFlag) throws(OCCTError) -> (shape: OCCTShape, history: [OCCTHistoryRecord]) {
        var history = occt_history()
        defer { occt_history_free(&history) }
        let shape = try Self.make { status in occt_thicken(self.raw, distance, Int32(side), cancel.raw, &history, status) }
        return (shape, OCCTHistoryRecord.read(history))
    }
}

extension OCCTKernel {
    static let thickenFoldedSentence = "The surface folds over itself, so it can't be thickened; move its control points apart first."

    /// How one try at a thickness ended.
    enum ThickenTry {
        case built(OCCTShape, [OCCTHistoryRecord])
        case failed(reason: String?)
    }

    /// R3, R7 to R9, R11, R17: `sheet` grown into a solid. The face on the sheet's back is its source's tags plus `.startCap`, the one
    /// on its front `.endCap`, and each wall `.blend(sourceEdge:)` of the boundary edge it stands on.
    public func thickened(_ sheet: Solid, distance: Double, side: ThickenSide, tag: NodeTag) async throws -> Solid {
        try Task.checkCancellation()
        let (source, limit) = try thickenSource(sheet, distance: distance, side: side)
        let first = try await thickenAttempt(source, distance: distance, side: side, limit: limit)
        if case .built(let shape, let history) = first {
            return try thickenedSolid(shape, history, of: sheet, tag: tag)
        }
        var firstReason: String?
        if case .failed(let reason) = first { firstReason = reason }
        let largest = try await largestValidOffset(below: distance, limit: limit) { magnitude in
            if case .built = try await self.thickenAttempt(source, distance: magnitude, side: side, limit: limit) { return true }
            return false
        }
        if largest == nil, let firstReason { throw KernelError.invalidInput(firstReason) }
        throw KernelError.offsetFailed(distance: distance, largest: largest, thickening: true)
    }

    /// R9, R11, R17 and R8's limit: the checks before any build. Gives the sheet's shape and the largest total thickness the
    /// curvature allows on `side` (Both uses half each way).
    func thickenSource(_ sheet: Solid, distance: Double, side: ThickenSide) throws -> (OCCTShape, Double) {
        guard distance.isFinite, distance > 0 else { throw KernelError.invalidInput("The distance must be greater than 0.") }
        guard sheet.hasOpenShell else { throw KernelError.invalidInput("Thicken takes a sheet; this is a closed solid.") }
        guard !sheet.holdsClosedSolid else {
            throw KernelError.invalidInput("Thicken takes sheets only; this value also holds a closed solid.")
        }
        guard try !folds(sheet) else { throw KernelError.invalidInput(Self.thickenFoldedSentence) }
        let source = try shape(of: sheet)
        let touching = try controlNetCall("thicken") { try source.touchingPieces() }
        guard !touching else { throw KernelError.invalidInput(Self.touchingSentence) }
        let above = try controlNetCall("thicken") { try source.offsetLimit(sign: 1) }
        let below = try controlNetCall("thicken") { try source.offsetLimit(sign: -1) }
        switch side {
        case .front: return (source, above)
        case .back: return (source, below)
        case .both: return (source, 2 * min(above, below))
        }
    }

    /// One build at `distance`, held to R8's curvature rule; a refusal of the shim is a failed try, a cancellation is thrown.
    func thickenAttempt(_ source: OCCTShape, distance: Double, side: ThickenSide, limit: Double) async throws -> ThickenTry {
        try Task.checkCancellation()
        guard distance < limit else { return .failed(reason: nil) }
        let flag = OCCTCancelFlag()
        do {
            let built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, history: [OCCTHistoryRecord]) in
                    try source.thicken(distance: distance, side: side.rawValue, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
            try Task.checkCancellation()
            return .built(built.shape, built.history)
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            return .failed(reason: Self.thickenFailureReason(error.message))
        }
    }

    /// What a failed try says to the user: only the open-edges sentence (R2), every other failure is a distance that doesn't work.
    static func thickenFailureReason(_ message: String) -> String? {
        message == thickenOpenEdgesSentence ? message : nil
    }

    func thickenedSolid(_ shape: OCCTShape, _ history: [OCCTHistoryRecord], of sheet: Solid, tag: NodeTag) throws -> Solid {
        try solid(from: shape, history: history, inputs: [sheet.topology], tag: tag, operation: "thicken")
    }
}
