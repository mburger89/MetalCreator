/// One level of the graph panel's header, "Graph › Rib › Hole pattern" (groups spec §6): the top level, then each
/// group entered. `depth` is what `EditorModel.goToLevel(_:)` takes.
public struct Breadcrumb: Equatable, Sendable, Identifiable {
    public var title: String
    public var depth: Int

    public var id: Int { depth }

    public init(title: String, depth: Int) {
        self.title = title
        self.depth = depth
    }
}
