#if canImport(CreatorOCCT)
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// `docs/examples/bracket-7.2.mcgraph`: the spec §7.2 bracket as the app's own save writes it (format `GraphFile.currentFormatVersion`),
/// the file human check XP-18 opens on Linux and Windows. The open test keeps the file honest: it must decode, evaluate with every
/// node OK, and make the same graph and the same part as the bracket the acceptance tests build in code, so a format change that
/// the file no longer survives, or a recipe change it no longer matches, fails here. To regenerate it after either, run
/// `MC_WRITE_EXAMPLES=1 swift test --filter BracketExampleTests` on a Mac and commit the result.
@MainActor
struct BracketExampleTests {
    static let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/examples/bracket-7.2.mcgraph")

    /// Writes the example through `AppModel.save(to:)`, the path File ▸ Save takes. Skipped unless asked for.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MC_WRITE_EXAMPLES"] != nil, "set MC_WRITE_EXAMPLES=1 to regenerate"))
    func regenerateTheExample() async throws {
        let (app, _) = try await makeBracketBenchApp()
        try Self.layOutLeftToRight(app)
        try app.save(to: Self.file)
    }

    /// The column of each node: one right of its furthest-left input's deepest source; a node with no inputs sits just before its first
    /// consumer rather than at the far left, so the wires stay short, and a column holds at most two of them, which is all the width
    /// of the default view has room for (a pair one lane apart is 240 wide).
    static func columns(of graph: Graph) -> [NodeID: Int] {
        var depth: [NodeID: Int] = [:]
        func depthOf(_ id: NodeID) -> Int {
            if let known = depth[id] { return known }
            let value = graph.links.filter { $0.to.node == id }.map { depthOf($0.from.node) + 1 }.max() ?? 0
            depth[id] = value
            return value
        }
        for id in graph.nodes.keys { _ = depthOf(id) }
        let sources = graph.nodes.values.filter { node in !graph.links.contains(where: { $0.to.node == node.id }) }
            .sorted { ($0.name, $0.typeID) < ($1.name, $1.typeID) }
        var inColumn: [Int: Int] = [:]
        for node in graph.nodes.values where !sources.contains(where: { $0.id == node.id }) {
            inColumn[depth[node.id] ?? 0, default: 0] += 1
        }
        for node in sources {
            let consumers = graph.links.filter { $0.from.node == node.id }.compactMap { depth[$0.to.node] }
            guard var column = consumers.min().map({ $0 - 1 }) else { continue }
            while inColumn[column, default: 0] >= 2 { column -= 1 }
            depth[node.id] = column
            inColumn[column, default: 0] += 1
        }
        let leftmost = depth.values.min() ?? 0
        return depth.mapValues { $0 - leftmost }
    }

    /// Moves every node to its column (`columns(of:)`), then places each column's nodes top to bottom, ordered by the mean height of
    /// what feeds them, at the free height nearest that mean. "Free" holds in both docks: the left dock draws the transpose of the
    /// positions but not of the sizes, so a pair needs room across the flow in one view and along it in the other (`isClear`). The
    /// saved view then starts at the flow (zoom 0.9 at the canvas's corner).
    static func layOutLeftToRight(_ app: AppModel) throws {
        let graph = app.document.graph
        let depth = columns(of: graph)
        let gap = 16.0, columnPitch = 160.0, step = 8.0
        // The saved view starts at the flow: drawn at `zoom` (rows show from 0.5), 16 points in from the canvas's corner. Nodes the
        // view reaches are wholly in it and the rest wholly out: a position that would put a node across its edge is passed over.
        let zoom = 0.9, margin = 16.0
        let flow = CanvasFlow(app.document.dock)
        let view = CanvasRect(origin: Vector2.zero,
                              size: defaultCanvasSize(dock: app.document.dock) * (1 / zoom))
        let limit = view.size - Vector2(margin, margin) * (1 / zoom)
        func isCut(_ origin: Vector2, _ size: Vector2) -> Bool {
            let frame = CanvasRect(origin: flow.display(origin), size: size)
            let inside = frame.origin.x >= 0 && frame.origin.y >= 0 && frame.maxX <= limit.x
                && frame.maxY <= limit.y
            let apart = frame.maxX <= 0 || frame.origin.x >= limit.x
                || frame.maxY <= 0 || frame.origin.y >= limit.y
            return !(inside || apart)
        }
        var placed: [(origin: Vector2, size: Vector2)] = []
        var top: [NodeID: Double] = [:]
        for column in 0...(depth.values.max() ?? 0) {
            let members = graph.nodes.values.filter { depth[$0.id] == column }
            func feed(_ node: Node) -> Double {
                let sources = graph.links.filter { $0.to.node == node.id }.compactMap { top[$0.from.node] }
                return sources.isEmpty ? 0 : sources.reduce(0, +) / Double(sources.count)
            }
            for node in members.sorted(by: { (feed($0), $0.name, $0.typeID) < (feed($1), $1.name, $1.typeID) }) {
                let size = NodeLayout.size(app.editor.shape(of: node))
                let x = Double(column) * columnPitch
                // The free height nearest the mean of the node's sources, trying the one above first.
                let wanted = max(0, (feed(node) / step).rounded() * step)
                var y = wanted, tries = 0
                while y < 0 || isCut(Vector2(x, y), size) || !isClear(Vector2(x, y), size, against: placed, gap: gap) {
                    tries += 1
                    y = wanted + Double((tries + 1) / 2) * step * (tries % 2 == 1 ? -1 : 1)
                }
                placed.append((Vector2(x, y), size))
                top[node.id] = y
                try app.document.perform(.move(node.id, to: Vector2(x, y)))
            }
        }
        app.document.canvasOffset = Vector2(margin, margin)
        app.document.canvasZoom = zoom
    }

    /// Whether a node of `size` at `origin` keeps `gap` points from every placed node in both docks' drawings: the stored rectangles
    /// (bottom dock) and their transposes with the sizes kept (left dock).
    static func isClear(_ origin: Vector2, _ size: Vector2, against placed: [(origin: Vector2, size: Vector2)], gap: Double) -> Bool {
        func apart(_ a: CanvasRect, _ b: CanvasRect) -> Bool {
            a.maxX + gap <= b.origin.x || b.maxX + gap <= a.origin.x || a.maxY + gap <= b.origin.y || b.maxY + gap <= a.origin.y
        }
        return placed.allSatisfy { other in
            apart(CanvasRect(origin: origin, size: size), CanvasRect(origin: other.origin, size: other.size))
                && apart(CanvasRect(origin: Vector2(origin.y, origin.x), size: size),
                         CanvasRect(origin: Vector2(other.origin.y, other.origin.x), size: other.size))
        }
    }

    /// The graph panel's canvas at the app's default sizes (window 1440 x 900, `AppLayout.defaultPanelWidth` and `defaultPanelHeight`,
    /// the library shown), in points: a left-docked panel is 480 wide and as tall as the window under the top bar, a bottom-docked
    /// one as wide as the window between the margins and the inspector and 300 tall.
    static func defaultCanvasSize(dock: DockSide) -> Vector2 {
        let window = Vector2(1440, 900)
        let panel = dock == .bottom
            ? Vector2(window.x - 3 * AppLayout.margin - AppLayout.inspectorWidth, AppLayout.defaultPanelHeight)
            : Vector2(AppLayout.defaultPanelWidth, window.y - 3 * AppLayout.margin - AppLayout.topBarHeight)
        return GraphPanelLayout.canvasFrame(inPanelOf: panel, flow: CanvasFlow(dock), showsLibrary: true).size
    }

    /// Every node's drawn frame in `dock`'s flow: the stored position transposed for the left dock, the size as `NodeLayout` has it.
    static func drawnFrames(_ app: AppModel, dock: DockSide) -> [(name: String, frame: CanvasRect)] {
        let flow = CanvasFlow(dock)
        return app.document.graph.nodes.values.map {
            (name: $0.name, frame: CanvasRect(origin: flow.display($0.position), size: NodeLayout.size(app.editor.shape(of: $0))))
        }
    }

    /// The example opens tidy: in either dock no two nodes touch (16 points apart at least; the left dock draws the transpose of
    /// the positions but not of the sizes, so both must hold), and in the file's own dock the saved view (zoom at least 0.75, so rows draw)
    /// starts at the flow: the inputs are wholly in the canvas at the default panel size and no node is cut by its edge.
    @Test func theExamplesNodesAreApartAndItsViewStartsTheFlowAtTheDefaultPanelSize() throws {
        let app = AppModel(kernel: OCCTKernel())
        try app.open(Self.file)
        let gap = 16.0
        for dock in [DockSide.left, .bottom] {
            let frames = Self.drawnFrames(app, dock: dock)
            for (index, a) in frames.enumerated() {
                for b in frames[(index + 1)...] {
                    let apart = a.frame.maxX + gap <= b.frame.origin.x || b.frame.maxX + gap <= a.frame.origin.x
                        || a.frame.maxY + gap <= b.frame.origin.y || b.frame.maxY + gap <= a.frame.origin.y
                    #expect(apart, "\(a.name) and \(b.name) are closer than \(gap) points in the \(dock) dock")
                }
            }
        }
        let dock = app.document.dock
        let canvas = CanvasRect(origin: .zero, size: Self.defaultCanvasSize(dock: dock))
        let zoom = app.document.canvasZoom
        #expect(zoom >= 0.75, "the saved zoom \(zoom) is near the \(EditorModel.rowsMinimumZoom) below which no rows draw")
        let transform = CanvasTransform(offset: app.document.canvasOffset, zoom: app.document.canvasZoom)
        let firstColumn = app.document.graph.nodes.values.map(\.position.x).min() ?? 0
        var inView = 0
        for node in app.document.graph.nodes.values {
            let frame = CanvasRect(origin: CanvasFlow(dock).display(node.position), size: NodeLayout.size(app.editor.shape(of: node)))
            let onScreen = CanvasRect(corner: transform.toScreen(frame.origin), transform.toScreen(frame.origin + frame.size))
            let inside = onScreen.origin.x >= canvas.origin.x && onScreen.origin.y >= canvas.origin.y
                && onScreen.maxX <= canvas.maxX && onScreen.maxY <= canvas.maxY
            let apart = onScreen.maxX <= canvas.origin.x || onScreen.origin.x >= canvas.maxX
                || onScreen.maxY <= canvas.origin.y || onScreen.origin.y >= canvas.maxY
            #expect(inside || apart, "\(node.name) is cut by the default view's edge")
            if node.position.x == firstColumn { #expect(inside, "the input \(node.name) is not wholly in the default view") }
            if inside { inView += 1 }
        }
        #expect(inView >= 4, "only \(inView) nodes are in the default view")
    }

    @Test func theCheckedInBracketOpensAndMakesTheCodeBuiltBracketsPart() async throws {
        let (built, _) = try await makeBracketBenchApp()
        let app = AppModel(kernel: OCCTKernel())
        try app.open(Self.file)
        await app.settle()
        expectAllOK(app, "the example file")
        // Node IDs are fresh UUIDs per build, so the recipes are compared by what they hold.
        func recipe(_ graph: Graph) -> [String] { graph.nodes.values.map { "\($0.typeID) \($0.name)" }.sorted() }
        #expect(recipe(app.document.graph) == recipe(built.document.graph), "the file holds the code-built recipe")
        #expect(app.document.graph.links.count == built.document.graph.links.count)
        #expect(app.document.graph.parameters.map(\.name) == built.document.graph.parameters.map(\.name))
        #expect(app.exportName == "Bracket")
        // Stored (left-to-right) frames: the dock only transposes how they are drawn.
        let frames = app.document.graph.nodes.values.map {
            (name: $0.name, frame: CanvasRect(origin: $0.position, size: NodeLayout.size(app.editor.shape(of: $0))))
        }
        for (index, a) in frames.enumerated() {
            for b in frames[(index + 1)...] {
                let apart = a.frame.maxX <= b.frame.origin.x || b.frame.maxX <= a.frame.origin.x
                    || a.frame.maxY <= b.frame.origin.y || b.frame.maxY <= a.frame.origin.y
                #expect(apart, "\(a.name) and \(b.name) overlap on the canvas")
            }
        }
        for link in app.document.graph.links {
            let from = try #require(app.document.graph.nodes[link.from.node]), to = try #require(app.document.graph.nodes[link.to.node])
            #expect(from.position.x < to.position.x, "\(from.name) feeds \(to.name) from the left")
        }
        let part = try #require(try app.exportSolids().first)
        let expected = try #require(try built.exportSolids().first)
        #expect(part.bounds == expected.bounds)
        let volume = try await app.kernel.properties(of: part).volume
        let expectedVolume = try await built.kernel.properties(of: expected).volume
        #expect(abs(volume - expectedVolume) <= 1e-9 * expectedVolume, "\(volume) against \(expectedVolume)")
    }
}
#endif
