import CreatorKernel
import Foundation

extension KernelError {
    /// OCCT couldn't build the blend at all.
    static func blendFailed(size: Double, chamfer: Bool) -> KernelError {
        if chamfer {
            return .operationFailed(operation: "chamfer",
                                    reason: "the selected edges can't be chamfered by \(millimetres(size)) mm.")
        }
        return .filletFailed(radius: size, maxRadius: nil, reason: "the selected edges can't be rounded this much.")
    }

    /// OCCT built the blend but its checker rejects the solid. `largest` is the largest size that gives a valid one,
    /// nil when not even 0.1 mm does.
    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError {
        let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? ", even by 0.1 mm"
            return .operationFailed(operation: "chamfer",
                                    reason: "chamfering \(edges) by \(millimetres(size)) mm gives a broken solid\(limit).")
        }
        let reason = largest == nil
            ? "rounding \(edges) gives a broken solid, even by 0.1 mm."
            : "rounding \(edges) by \(millimetres(size)) mm gives a broken solid."
        return .filletFailed(radius: size, maxRadius: largest, reason: reason)
    }

    private static func millimetres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
