import CreatorGeometry
import CreatorGraph

/// Wires and cable ties on the canvas (cable ties spec 2026-10-26 §4, §5).
extension EditorModel {
    /// The level's wires and ties as drawn: every link's taut route and every tie's lanes and band, in display canvas
    /// points, from the socket anchors. Hit testing, boxes, culling and ⌘⇧T read it. It is computed each time it is read,
    /// never stored.
    public var wireRouting: WireRouting {
        var outputs: [Endpoint: Vector2] = [:]
        var inputs: [Endpoint: Vector2] = [:]
        for link in graph.links {
            outputs[link.from] = anchor(of: SocketRef(link.from, isInput: false))
            inputs[link.to] = anchor(of: SocketRef(link.to, isInput: true))
        }
        return WireRouting(links: graph.links, ties: graph.ties, outputs: outputs, inputs: inputs, flow: flow)
    }

    /// Ties back to front: by ID, with the selected ones raised above the rest.
    public func drawOrderTies(in routing: WireRouting) -> [TieLayout] {
        routing.ties.values.sorted { a, b in
            let aSelected = canvasSelection.ties.contains(a.id), bSelected = canvasSelection.ties.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }
}
