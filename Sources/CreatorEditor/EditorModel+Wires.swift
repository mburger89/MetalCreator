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

    /// How close to a wire's taut route a press still hits it, in display canvas points (cable ties spec §4.1).
    public static let wireHitDistance = 5.0

    /// The frontmost tie whose band holds `point` (display canvas points).
    func tieHit(at point: Vector2, in routing: WireRouting) -> TieID? {
        drawOrderTies(in: routing).last { $0.band.contains(point) }?.id
    }

    /// The wire whose taut route passes nearest `point`, within `wireHitDistance`; on a tie, the lower endpoint.
    func wireHit(at point: Vector2, in routing: WireRouting) -> Endpoint? {
        routing.routes.values
            .map { ($0.wire, $0.distance(to: point)) }
            .filter { $0.1 <= Self.wireHitDistance }
            .min { ($0.1, $0.0) < ($1.1, $1.0) }?.0
    }
}
