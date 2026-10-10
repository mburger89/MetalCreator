import CreatorKernel

extension OCCTKernel {
    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `OCCTShape.isValid` rejects is never returned: the blend fails, naming the largest size that works.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let built: (OCCTShape, [OCCTHistoryRecord])?
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            built = try Self.serialized { () throws -> (OCCTShape, [OCCTHistoryRecord])? in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                return result.0.isValid ? result : nil
            }
        } catch is OCCTError {
            throw KernelError.blendFailed(size: size, chamfer: chamfer)
        }
        guard let built else {
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
        return try self.solid(from: built.0, history: built.1, inputs: [solid.topology], tag: tag,
                              operation: chamfer ? "chamfer" : "fillet")
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and its checker accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool) throws -> Double? {
        var works = 0
        // In tenths of a millimetre; capped so a huge size can't overflow `Int` (sizes above it are never tried).
        var fails = Int(min((size * 10).rounded(.up), 1_000_000))
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let valid = Self.serialized { () -> Bool in
                (try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer))?.0.isValid ?? false
            }
            if valid { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
