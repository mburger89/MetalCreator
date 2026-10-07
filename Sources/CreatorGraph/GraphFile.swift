/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var graph: Graph
    public var viewState: ViewState

    public init(formatVersion: Int = GraphFile.currentFormatVersion, graph: Graph = Graph(), viewState: ViewState = ViewState()) {
        self.formatVersion = formatVersion
        self.graph = graph
        self.viewState = viewState
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, graph, viewState }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        graph = try container.decode(Graph.self, forKey: .graph)
        viewState = try container.decodeIfPresent(ViewState.self, forKey: .viewState) ?? ViewState()
    }
}
