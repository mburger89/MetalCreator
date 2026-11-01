import COCCT
import CreatorKernel

/// Whether a curvature-continuous fillet's spring seams keep the promise (position 1e-4 mm, angle 0.01 degrees,
/// curvature within its allowance), judged on the shim's report at a radius. A test passes another to force a miss.
struct G2SeamCheck: Sendable {
    let passes: @Sendable (occt_g2_report, Double) -> Bool

    static let promised = G2SeamCheck { report, _ in
        withUnsafeBytes(of: report.seams) { raw in
            raw.bindMemory(to: occt_g2_seam.self).prefix(Int(report.seam_count)).allSatisfy {
                $0.position <= 1e-4 && $0.angle_degrees <= 0.01 && $0.curvature_ratio <= 1
            }
        }
    }
}

extension OCCTKernel {
    /// What one try at a blend came to.
    private enum Attempt {
        case built(OCCTShape, [OCCTHistoryRecord], occt_g2_report?)
        /// A G2 strip misses the promised continuity (or the shim could not build it).
        case stripMissed
        /// The shim refused a weight or a corner in its own words.
        case refused(String)
        /// OCCT built a solid its checker rejects.
        case rejected
        /// OCCT built a solid and the checker itself failed.
        case unchecked
        /// OCCT reported the blend not done.
        case notBuilt
    }

    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `check` rejects is never returned: the blend fails, naming the largest size that works. A blend OCCT
    /// can't build at all fails the same way (Errata (Kernel: largest size for blends OCCT can't build)); either search
    /// costs up to about 20 failing tries. `check` is `OCCTShape.validity`; a test passes another to stand in for a
    /// checker that throws or rejects every size, or to count the tries.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag,
               check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Solid {
        try blendReporting(solid, edges: edges, size: size, chamfer: chamfer, profile: .circular, tag: tag, check: check).solid
    }

    /// `blend` with a profile; a curvature-continuous fillet also gives the shim's report. A G2 strip that misses the
    /// promise fails naming the largest radius whose G2 build passes (`seamCheck` judges it; a test passes another).
    func blendReporting(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, profile: FilletProfile, tag: NodeTag,
                        seamCheck: G2SeamCheck = .promised,
                        check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> (solid: Solid, report: occt_g2_report?) {
        try profile.validate()
        let source = try blendSource(solid, edges: edges, size: size)
        let tried = try attempt(blending: source, edges: edges, size: size, style: (chamfer, profile),
                                seamCheck: seamCheck, check: check)
        switch tried {
        case .built(let shape, let history, let report):
            let made = try self.solid(from: shape, history: history, inputs: [solid.topology], tag: tag,
                                      operation: chamfer ? "chamfer" : "fillet")
            return (made, report)
        case .unchecked:
            // A checker that threw says nothing about any size, so there is nothing to search for.
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: nil)
        case .refused(let message):
            throw KernelError.invalidInput(message)
        case .stripMissed:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, profile: profile,
                                                seamCheck: seamCheck, check: check)
            throw KernelError.notCurvatureContinuous(radius: size, largest: largest)
        case .notBuilt:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, profile: profile,
                                                seamCheck: seamCheck, check: check)
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: largest)
        case .rejected:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, profile: profile,
                                                seamCheck: seamCheck, check: check)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
    }

    /// Builds the blend once under the OCCT lock and sorts what came of it.
    private func attempt(blending source: OCCTShape, edges: [EdgeID], size: Double, style: (chamfer: Bool, profile: FilletProfile),
                         seamCheck: G2SeamCheck, check: (OCCTShape) -> OCCTValidity) throws -> Attempt {
        let (chamfer, profile) = style
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            return try Self.serialized { () throws -> Attempt in
                switch profile {
                case .circular:
                    let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                    return Self.judge(result.0, result.1, nil, check)
                case .curvatureContinuous(let weight):
                    let result = try source.blendedCurvatureContinuous(edges: edges, size: size, weight: weight)
                    if !seamCheck.passes(result.report, size) { return .stripMissed }
                    return Self.judge(result.shape, result.history, result.report, check)
                }
            }
        } catch let error as OCCTError {
            guard case .curvatureContinuous = profile else { return .notBuilt }
            switch error.message {
            case Self.weightMessage, Self.cornerMessage: return .refused(error.message)
            case KernelError.notCurvatureContinuousSentence: return .stripMissed
            default: return .notBuilt
            }
        }
    }

    /// Sorts a built blend by what the validity check says.
    private static func judge(_ shape: OCCTShape, _ history: [OCCTHistoryRecord], _ report: occt_g2_report?,
                              _ check: (OCCTShape) -> OCCTValidity) -> Attempt {
        switch check(shape) {
        case .valid: .built(shape, history, report)
        case .invalid: .rejected
        case .unchecked: .unchecked
        }
    }

    /// The shim's own refusals of a curvature-continuous fillet (`cocct_g2_blend.cpp`).
    private static let weightMessage = "The tangency weight is too large for this fillet."
    private static let cornerMessage = "The fillet's corners can't be made smooth at this radius."

    /// The OCCT shape of `solid`, once the blend's size and edges are known to make sense for it.
    private func blendSource(_ solid: Solid, edges: [EdgeID], size: Double) throws -> OCCTShape {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        return try shape(of: solid)
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts (asked a second
    /// time when it can't judge); nil when not even 0.1 mm does. It bisects, assuming every size above one that fails
    /// fails too; the size it returns was built and checked. Each try takes the OCCT lock on its own, and a cancelled
    /// evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                           profile: FilletProfile = .circular, seamCheck: G2SeamCheck = .promised,
                           check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
        var works = 0
        // In tenths of a millimetre (sizes above `BlendGrid.mostTenths` are never tried).
        var fails = BlendGrid.firstFailingTenths(for: size)
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let radius = Double(tenths) / 10
            // A G2 radius passes only if its build succeeds, its seams pass and the solid is valid. A checker that can't
            // judge says nothing about the size: it gets one more look before it fails.
            var tried = try attempt(blending: source, edges: edges, size: radius, style: (chamfer, profile),
                                    seamCheck: seamCheck, check: check)
            if case .unchecked = tried {
                tried = try attempt(blending: source, edges: edges, size: radius, style: (chamfer, profile),
                                    seamCheck: seamCheck, check: check)
            }
            if case .built = tried { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
