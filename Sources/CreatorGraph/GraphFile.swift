import Foundation

/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. 4: adds the `sketch` and `facePick` setting
    /// kinds (S4), which a version-3 reader can't decode. 5: adds group definitions (groups spec §2, §4), which a
    /// version-4 reader would drop while keeping group nodes that name them. 6: the Lists & Trees nodes (7a: data
    /// trees) keep text settings (`NodeSetting.pathRule`, `NodeSetting.branchPath`, `NodeSetting.itemPath`) that a
    /// version-5 reader would show as a node it can't run. Trees themselves are computed, never saved. Version-1 to -5
    /// files still load unchanged. Canvas comments (`Graph.stickies`, `Graph.frames`) add optional keys under 5: no bump.
    /// 7: the Image Field's `image` setting (`ConstantValue.image`) and the optional top-level `images` table of embedded
    /// pictures (fields spec §5), and a group interface may now carry a `field` socket (7b-1 refused it under 6); a
    /// version-6 reader can decode none of these. Version-1 to -6 files open unchanged and are written as 7.
    public static let currentFormatVersion = 7

    public var formatVersion: Int
    public var graph: Graph
    /// The document's group definitions (groups spec §4). Written as an array sorted by ID; absent in older files.
    public var definitions: [GroupID: GroupDefinition]
    public var viewState: ViewState
    /// The embedded images, by the hash of their bytes (fields spec §5): the file's own PNG or JPEG bytes, written as base64
    /// under their SHA-256 in a top-level `images` object (sorted by key), only when there are some. A damaged entry is
    /// left out on reading (`ImageTable`).
    public var images: [ImageHash: Data]

    public init(formatVersion: Int = GraphFile.currentFormatVersion, graph: Graph = Graph(),
                definitions: [GroupID: GroupDefinition] = [:], viewState: ViewState = ViewState(),
                images: [ImageHash: Data] = [:]) {
        self.formatVersion = formatVersion
        self.graph = graph
        self.definitions = definitions
        self.viewState = viewState
        self.images = images
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, graph, definitions, viewState, images }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        graph = try container.decode(Graph.self, forKey: .graph)
        let list = try container.decodeIfPresent([GroupDefinition].self, forKey: .definitions) ?? []
        definitions = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        viewState = try container.decodeIfPresent(ViewState.self, forKey: .viewState) ?? ViewState()
        // A table of the wrong shape is ignored, and a damaged entry left out, not fatal: the nodes that point at them report
        // their images missing.
        images = ImageTable.decode((try? container.decodeIfPresent([String: ImageTable.Entry].self, forKey: .images)) ?? [:])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(graph, forKey: .graph)
        try container.encode(definitions.values.sorted { $0.id < $1.id }, forKey: .definitions)
        try container.encode(viewState, forKey: .viewState)
        if !images.isEmpty { try container.encode(ImageTable.encode(images), forKey: .images) }
    }
}
