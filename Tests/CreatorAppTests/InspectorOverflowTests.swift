import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The inspector is bounded by the window (display finding 1): a long Data path list scrolls inside the glass instead of
/// growing the panel past the window's bottom.
@MainActor
struct InspectorOverflowTests {
    func render(_ app: AppModel, height: Double = 900) -> Scene {
        let input = AppInput(model: app)
        return renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(Float(height))),
                           scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
    }

    /// Series (count 120) → Partition (size 2): 60 branches, so the path list is cut at 50 and says "and 10 more".
    func partitionApp() async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let series = builder.add(SeriesNode.self, ["start": .number(0), "step": .number(1), "count": .integer(120)])
        let partition = builder.add(PartitionNode.self, ["size": .integer(2)])
        builder.wire(series, "values", to: partition, "tree")
        let app = await makeApp(builder.graph)
        app.previewMode = .selectedNode
        app.editor.selection = [partition.id]
        await app.settle()
        return (app, partition)
    }

    /// The inspector's glass: the rect `AppLayout.inspectorWidth` wide, in window points as (top, bottom).
    func inspectorGlass(_ scene: Scene) -> (top: Double, bottom: Double)? {
        let glass = scene.rects.filter { abs(Double($0.bounds.size.width) / 2 - AppLayout.inspectorWidth) < 0.5 }
        return glass.map { (Double($0.bounds.origin.y) / 2, Double($0.bounds.origin.y + $0.bounds.size.height) / 2) }
            .max { $0.bottom - $0.top < $1.bottom - $1.top }
    }

    @Test func aLongPathListStaysInsideTheWindow() async throws {
        let (app, partition) = await partitionApp()
        let short = try #require(inspectorGlass(render(app)))
        app.editor.toggleShapeList(TreeShapeRow.key(node: partition.id, isInput: false, socket: "tree"))
        await app.settle()
        #expect(app.editor.inspectorPage.sections.contains { $0.rows.contains { if case .treeShape(let row) = $0 { row.isExpanded } else { false } } })
        let long = try #require(inspectorGlass(render(app)))
        let below = AppLayout.margin * 2 + AppLayout.topBarHeight
        #expect(long.top >= below - 0.5, "the inspector stays below the top bar: \(long.top)")
        #expect(long.bottom <= 900 - AppLayout.margin + 0.5, "and above the window's bottom margin: \(long.bottom)")
        #expect(short.bottom - short.top < long.bottom - long.top, "a short page is not a full-height column")
        #expect(short.top >= below - 0.5 && short.bottom < 900 - 100)
    }

    @Test func aShortWindowBoundsTheInspectorToo() async throws {
        let (app, _) = await partitionApp()
        let glass = try #require(inspectorGlass(render(app, height: 300)))
        #expect(glass.bottom <= 300 - AppLayout.margin + 0.5, "the page scrolls inside a 300-point window: \(glass.bottom)")
    }
}
