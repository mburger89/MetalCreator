import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Turns the field wired into a setting (a blend radius, a thickness, an offset) into the `Grading` an implicit solid holds, and says
/// what is worth warning about (implicit spec §3.3).
enum ImplicitGrading {
    /// What a setting came to: the grading, and the warnings it earned.
    struct Result {
        var grading: Grading
        var warnings: [String]
    }

    /// The grading of `name`'s field over `region`.
    /// - Parameters:
    ///   - holdsAtZero: whether a value below 0 is held at 0 (a blend radius, a thickness), which earns a warning where the field is.
    static func make(_ field: Field, named name: SocketName, over region: BoundingBox, holdsAtZero: Bool,
                     kernel: any Kernel, context: EvalContext) async throws -> Result {
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel, cache: context.fieldDistances)
        var warnings: [String] = []
        if !field.slopeBound.isKnown {
            warnings.append("“\(name)” changes at a rate that isn't known, so the preview may be slow.")
        }
        if holdsAtZero, grading.constantValue == nil, grading.range.lowerBound < 0 {
            warnings.append("“\(name)” is below 0 in places; it is held at 0 there.")
        }
        return Result(grading: grading, warnings: warnings)
    }

    /// A box around `box` with room for a setting that makes the shape bigger: 20% of its longest side, at least a millimetre.
    static func region(around box: BoundingBox) -> BoundingBox {
        let longest = max(box.size.x, box.size.y, box.size.z)
        return ImplicitSolid.grown(box, by: max(1, longest * 0.2))
    }
}
