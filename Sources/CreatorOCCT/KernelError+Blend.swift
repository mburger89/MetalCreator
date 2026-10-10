import CreatorKernel
import Foundation

extension KernelError {
    /// OCCT couldn't build the blend (or its checker failed). `largest` is the largest size that works, nil when none
    /// was found or looked for.
    static func blendFailed(size: Double, chamfer: Bool, largest: Double?, locale: Locale = .messages) -> KernelError {
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0, locale)) mm)" } ?? ""
            return .operationFailed(operation: "chamfer",
                                    reason: "the selected edges can't be chamfered by \(millimetres(size, locale)) mm\(limit).")
        }
        return .filletFailed(radius: size, maxRadius: largest, reason: "the selected edges can't be rounded this much.")
    }

    /// OCCT built the blend but its checker rejects the solid. `largest` is the largest size that gives a valid one,
    /// nil when none was found: then the message adds "even by 0.1 mm" only if 0.1 mm was tried (`size` above it).
    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool,
                             locale: Locale = .messages) -> KernelError {
        let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
        let noneFound = BlendGrid.triesSmallest(below: size) ? ", even by \(millimetres(BlendGrid.step, locale)) mm" : ""
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0, locale)) mm)" } ?? noneFound
            return .operationFailed(operation: "chamfer",
                                    reason: "chamfering \(edges) by \(millimetres(size, locale)) mm gives a broken solid\(limit).")
        }
        let reason = largest == nil
            ? "rounding \(edges) gives a broken solid\(noneFound)."
            : "rounding \(edges) by \(millimetres(size, locale)) mm gives a broken solid."
        return .filletFailed(radius: size, maxRadius: largest, reason: reason)
    }

    /// `Double.millimetreText`, the formatter `KernelError.userMessage` uses too.
    private static func millimetres(_ value: Double, _ locale: Locale) -> String {
        value.millimetreText(locale: locale)
    }
}
