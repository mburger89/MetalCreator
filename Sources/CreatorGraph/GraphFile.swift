/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. 4: adds the `sketch` and `facePick` setting
    /// kinds (S4), which a version-3 reader can't decode. Version-1 to -3 files still load unchanged.
    public static let currentFormatVersion = 4

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
