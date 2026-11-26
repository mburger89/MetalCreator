import CreatorGeometry

extension Kernel {
    public func cutAwayNoting(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws
        -> (solid: Solid?, warnings: [String]) {
        (try await cutAway(solid, by: cutter, tag: tag), [])
    }

    public func cutAway(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws -> Solid? {
        throw KernelError.unsupported("cutting sections")
    }
}
