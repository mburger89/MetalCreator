import CreatorGraph
import Testing
@testable import CreatorEditor

/// The panels around the canvas are `.equatable()` (MetalUI C14-d): `==` compares the model and the input by identity, and
/// nothing else, because both are final classes whose observed reads MetalUI tracks itself. One test per view: the same
/// objects are equal, and a second model (or a second input over it) is not.
@MainActor
struct PanelEqualityTests {
    let model = makeEditor([])
    let other = makeEditor([])

    @Test func aNodeLibraryViewIsEqualOnlyForTheSameModelAndInput() {
        let input = GraphPanelInput(model: model)
        #expect(NodeLibraryView(model: model, input: input) == NodeLibraryView(model: model, input: input))
        #expect(NodeLibraryView(model: model, input: input) != NodeLibraryView(model: other, input: input))
        #expect(NodeLibraryView(model: model, input: input) != NodeLibraryView(model: model, input: GraphPanelInput(model: model)))
    }

    @Test func anInspectorPanelIsEqualOnlyForTheSameModel() {
        #expect(InspectorPanel(model: model) == InspectorPanel(model: model))
        #expect(InspectorPanel(model: model) != InspectorPanel(model: other))
    }

    @Test func aGraphCanvasIsEqualOnlyForTheSameModelAndInput() {
        let input = GraphPanelInput(model: model)
        #expect(GraphCanvas(model: model, input: input) == GraphCanvas(model: model, input: input))
        #expect(GraphCanvas(model: model, input: input) != GraphCanvas(model: other, input: input))
        #expect(GraphCanvas(model: model, input: input) != GraphCanvas(model: model, input: GraphPanelInput(model: model)))
    }

    @Test func aCanvasSurfaceIsEqualOnlyForTheSameModelAndInput() {
        let input = GraphPanelInput(model: model)
        #expect(CanvasSurface(model: model, input: input) == CanvasSurface(model: model, input: input))
        #expect(CanvasSurface(model: model, input: input) != CanvasSurface(model: other, input: input))
        #expect(CanvasSurface(model: model, input: input) != CanvasSurface(model: model, input: GraphPanelInput(model: model)))
    }

    @Test func aGraphPanelBodyIsEqualOnlyForTheSameModelAndInput() {
        let input = GraphPanelInput(model: model)
        #expect(GraphPanelBody(model: model, input: input) == GraphPanelBody(model: model, input: input))
        #expect(GraphPanelBody(model: model, input: input) != GraphPanelBody(model: other, input: input))
        #expect(GraphPanelBody(model: model, input: input) != GraphPanelBody(model: model, input: GraphPanelInput(model: model)))
    }

    @Test func aGraphPanelIsEqualOnlyForTheSameModelAndInput() {
        let input = GraphPanelInput(model: model)
        #expect(GraphPanel(model: model, input: input) == GraphPanel(model: model, input: input))
        #expect(GraphPanel(model: model, input: input) != GraphPanel(model: other, input: input))
        #expect(GraphPanel(model: model, input: input) != GraphPanel(model: model, input: GraphPanelInput(model: model)))
    }
}
