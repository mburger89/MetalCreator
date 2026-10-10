/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. 4: adds the `sketch` and `facePick` setting
    /// kinds (S4), which a version-3 reader can't decode. 5: adds group definitions (groups spec §2, §4), which a
    /// version-4 reader would drop while keeping group nodes that name them. Version-1 to -4 files still load unchanged.
    public static let currentFormatVersion = 5

    public var formatVersion: Int
    public var graph: Graph
    /// The document's group definitions (groups spec §4). Written as an array sorted by ID; absent in older files.
    public var definitions: [GroupID: GroupDefinition]
    public var viewState: ViewState

    public init(formatVersion: Int = GraphFile.currentFormatVersion, graph: Graph = Graph(),
                definitions: [GroupID: GroupDefinition] = [:], viewState: ViewState = ViewState()) {
        self.formatVersion = formatVersion
        self.graph = graph
        self.definitions = definitions
        self.viewState = viewState
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, graph, definitions, viewState }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        graph = try container.decode(Graph.self, forKey: .graph)
        let list = try container.decodeIfPresent([GroupDefinition].self, forKey: .definitions) ?? []
        definitions = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        viewState = try container.decodeIfPresent(ViewState.self, forKey: .viewState) ?? ViewState()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(graph, forKey: .graph)
        try container.encode(definitions.values.sorted { $0.id < $1.id }, forKey: .definitions)
        try container.encode(viewState, forKey: .viewState)
    }
}
