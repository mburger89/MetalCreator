extension GraphCommand {
    /// This command addressed to the graph at `path` (groups spec §5): itself on the top level, `.inDefinition`
    /// inside a group.
    public func at(_ path: GraphPath) -> GraphCommand {
        switch path {
        case .root: self
        case .definition(let id): .inDefinition(id, self)
        }
    }
}
