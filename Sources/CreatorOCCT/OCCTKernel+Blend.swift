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
    /// result `check` rejects is never returned: the blend fails, naming the largest size that works. A blend OCCT
    /// can't build at all fails the same way (Errata (Kernel: largest size for blends OCCT can't build)); either search
    /// costs up to about 20 failing tries. `check` is `OCCTShape.validity`; a test passes another to stand in for a
    /// checker that throws or rejects every size, or to count the tries.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag,
               check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Solid {
        let source = try blendSource(solid, edges: edges, size: size)
        switch try attempt(blending: source, edges: edges, size: size, chamfer: chamfer, check: check) {
        case .built(let shape, let history):
            return try self.solid(from: shape, history: history, inputs: [solid.topology], tag: tag,
                                  operation: chamfer ? "chamfer" : "fillet")
        case .unchecked:
            // A checker that threw says nothing about any size, so there is nothing to search for.
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: nil)
        case .notBuilt:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: largest)
        case .rejected:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
    }

    /// Builds the blend once under the OCCT lock and sorts what came of it.
    private func attempt(blending source: OCCTShape, edges: [EdgeID], size: Double, chamfer: Bool,
                         check: (OCCTShape) -> OCCTValidity) throws -> Attempt {
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            return try Self.serialized { () throws -> Attempt in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                switch check(result.0) {
                case .valid: return .built(result.0, result.1)
                case .invalid: return .rejected
                case .unchecked: return .unchecked
                }
            }
        } catch is OCCTError {
            return .notBuilt
        }
    }

    /// The OCCT shape of `solid`, once the blend's size and edges are known to make sense for it.
    private func blendSource(_ solid: Solid, edges: [EdgeID], size: Double) throws -> OCCTShape {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        return try shape(of: solid)
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                           check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
        var works = 0
        // In tenths of a millimetre (sizes above `BlendGrid.mostTenths` are never tried).
        var fails = BlendGrid.firstFailingTenths(for: size)
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
