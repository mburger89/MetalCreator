import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Spec §3.3's bar: no two dimension labels overlap on the bracket from the default views (DIM-3 Task 16).
@MainActor
struct BracketDimensionOverlapTests {
    /// 8 points a character, as the declutter tests measure.
    let measure = TextMeasure { text in ViewportSize(width: Double(text.count) * 8, height: 12) }

    @Test func theDefaultBracketViewsHaveNoOverlap() async throws {
        var plate = FeatureClickTests.Plate()
        plate.builder.graph.dimensionPins = [DimensionPin(node: plate.extrude.id, target: .input("distance"))]
        let app = await makeApp(plate.builder.graph)
        app.editor.selection = [plate.holes.id]
        await app.settle()
        let viewport = app.viewport
        viewport.viewSize = ViewportSize(width: 1100, height: 700)
        let shown = viewport.dimensions
        try #require(shown.count >= 3, "the pattern's dimensions and the pinned length: \(shown.map(\.id.rawValue))")
        #expect(shown.contains { $0.isPinned })
        let bounds = try #require(viewport.sceneBounds)

        var poses = [("home", viewport.homePose ?? viewport.defaultHome(for: bounds))]
        for region in ViewCubeRegion.faces + [.isometric] {
            poses.append((region.label ?? "isometric", region.pose(from: poses[0].1)))
        }
        var drawn = 0
        for (name, pose) in poses {
            viewport.pose = pose
            let placed = viewport.placedDimensions(measuring: measure)
            // A plane seen edge-on leaves its dimensions out (DimensionStyle.edgeOnLimit), so only some views draw any.
            if ["home", "TOP", "BOTTOM"].contains(name) { #expect(!placed.isEmpty, "\(name) draws dimensions") }
            drawn += placed.count
            for (index, first) in placed.enumerated() {
                for second in placed[(index + 1)...] {
                    let apart = first.textOrigin.x + first.textSize.width <= second.textOrigin.x
                        || second.textOrigin.x + second.textSize.width <= first.textOrigin.x
                        || first.textOrigin.y + first.textSize.height <= second.textOrigin.y
                        || second.textOrigin.y + second.textSize.height <= first.textOrigin.y
                    #expect(apart, "\(name): \(first.id.rawValue) and \(second.id.rawValue) overlap")
                }
            }
        }
        #expect(drawn > 0)
    }
}
