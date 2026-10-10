import CreatorKernel

extension OCCTKernel {
    /// What one try at a blend came to.
    private enum Attempt {
        case built(OCCTShape, [OCCTHistoryRecord])
        /// OCCT built a solid its checker rejects.
        case rejected
        /// OCCT built a solid and the checker itself failed.
        case unchecked
        /// OCCT reported the blend not done.
        case notBuilt
    }

    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `check` rejects is never returned: the blend fails, naming the largest size that works. `check` is
    /// `OCCTShape.validity`; a test passes another to stand in for a checker that throws or rejects every size, or to
    /// count the tries.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag,
               check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let attempt: Attempt
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            attempt = try Self.serialized { () throws -> Attempt in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                switch check(result.0) {
                case .valid: return .built(result.0, result.1)
                case .invalid: return .rejected
                case .unchecked: return .unchecked
                }
            }
        } catch is OCCTError {
            attempt = .notBuilt
        }
        switch attempt {
        case .built(let shape, let history):
            return try self.solid(from: shape, history: history, inputs: [solid.topology], tag: tag,
                                  operation: chamfer ? "chamfer" : "fillet")
        case .unchecked, .notBuilt:
            // A checker that threw says nothing about any size, so there is nothing to search for.
            throw KernelError.blendFailed(size: size, chamfer: chamfer)
        case .rejected:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                           check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
        var works = 0
        // In tenths of a millimetre; capped so a huge size can't overflow `Int` (sizes above it are never tried).
        var fails = Int(min((size * 10).rounded(.up), 1_000_000))
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let valid = Self.serialized { () -> Bool in
                guard let built = try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer) else { return false }
                return check(built.0) == .valid
            }
            if valid { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
