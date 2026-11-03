import CreatorGeometry

extension FakeKernel {
    public func loft(
        _ sections: [Profile2D], ruled: Bool, part: Solid?, start: LoftEnd?, end: LoftEnd?, tag: NodeTag
    ) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("loft")
        guard sections.allSatisfy(\.holes.isEmpty) else {
            throw KernelError.loftWithHoles
        }
        try Self.validateLoftEnds(sections: sections.count, ruled: ruled, part: part, start: start, end: end)
        if start != nil || end != nil {
            throw KernelError.unsupported("loft end conditions")
        }
        throw KernelError.unsupported("loft")
    }
}
