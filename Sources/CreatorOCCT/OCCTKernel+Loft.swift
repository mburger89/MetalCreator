import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    public func loft(
        _ sections: [Profile2D], ruled: Bool, part: Solid?, start: LoftEnd?, end: LoftEnd?, tag: NodeTag
    ) throws -> Solid {
        try Task.checkCancellation()
        guard start != nil || end != nil else {
            // Profiles alone: exactly today's loft.
            guard sections.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
            guard sections.allSatisfy(\.holes.isEmpty) else { throw KernelError.loftWithHoles }
            try checkSections(sections)
            return try build("loft", inputs: [], tag: tag) { try OCCTShape.loft(sections, ruled: ruled) }
        }
        guard sections.allSatisfy(\.holes.isEmpty) else { throw KernelError.loftWithHoles }
        try Self.validateLoftEnds(sections: sections.count, ruled: ruled, part: part, start: start, end: end)
        try checkSections(sections)
        let source = try part.map { try shape(of: $0) }
        // None of the part's faces are in the loft, so no tag of the part passes through (`inputs` is empty).
        return try build("loft", inputs: [], tag: tag) {
            do {
                let built = try OCCTShape.loftEnds(part: source, start: start, end: end, sections: sections)
                return (built.shape, built.history)
            } catch let error as OCCTError where KernelError.loftShimSentences.contains(error.message) {
                throw KernelError.invalidInput(error.message)
            }
        }
    }

    /// The profiles of a loft agree on their segment count and are closed loops on a valid plane.
    private func checkSections(_ sections: [Profile2D]) throws {
        guard Set(sections.map(\.segments.count)).count <= 1 else {
            throw KernelError.invalidInput("Every loft section needs the same number of segments.")
        }
        for section in sections { try Self.validate(section.plane) }
        guard sections.allSatisfy(\.isClosed) else { throw KernelError.invalidInput("The profile is not a closed loop.") }
    }
}
