import CreatorKernel
import CreatorViewport

/// Click-to-select for the harness. The viewport only reports clicks (selection belongs to the app shell, M6), so
/// the harness applies them itself: a face selects it and its edges, an edge selects that edge, empty space clears.
@MainActor
final class HarnessSelection {
    private(set) var items: [ViewportItem] = []

    func show(_ items: [ViewportItem], on model: ViewportModel) {
        self.items = items
        model.show(items)
    }

    func apply(_ target: PickTarget?, on model: ViewportModel) {
        guard !items.isEmpty else { return }
        for index in items.indices {
            items[index].selectedFaces = []
            items[index].selectedEdges = []
        }
        switch target {
        case .face(let solid, let face) where items.indices.contains(solid):
            let edges = items[solid].solid.topology.edges.filter { !$0.isSeam && $0.faces.contains(face) }
            items[solid].selectedFaces = [face]
            items[solid].selectedEdges = Set(edges.map(\.id))
        case .edge(let solid, let edge) where items.indices.contains(solid):
            items[solid].selectedEdges = [edge]
        default:
            break
        }
        model.show(items)
    }

    func selectEdges(_ edges: [EdgeID], ofSolid solid: Int, on model: ViewportModel) {
        guard items.indices.contains(solid) else { return }
        for index in items.indices {
            items[index].selectedFaces = []
            items[index].selectedEdges = []
        }
        items[solid].selectedEdges = Set(edges)
        model.show(items)
    }
}
