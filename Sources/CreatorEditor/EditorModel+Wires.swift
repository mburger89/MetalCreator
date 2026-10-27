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

    /// The wires whose taut route crosses or lies inside `rect` (display canvas points), each with the centre of the middles
    /// of its stretches inside it: what an ⌥-box finds (cable ties spec §4.1, §4.2).
    func wires(intersecting rect: CanvasRect, in routing: WireRouting) -> [Endpoint: Vector2] {
        routing.routes.values.reduce(into: [:]) { found, route in
            let inside = route.pointsInside(rect)
            guard !inside.isEmpty else { return }
            found[route.wire] = inside.reduce(Vector2.zero, +) * (1 / Double(inside.count))
        }
    }

    /// The ties whose band lies wholly inside `rect`: what a plain box picks up (cable ties spec §4.1).
    func ties(inside rect: CanvasRect, in routing: WireRouting) -> Set<TieID> {
        Set(routing.ties.values.filter { rect.contains($0.band.origin) && rect.contains(Vector2($0.band.maxX, $0.band.maxY)) }
            .map(\.id))
    }

    /// The box being dragged on empty canvas, plain or ⌥ (display canvas points); `nil` while there is none.
    public var selectionBox: CanvasRect? {
        switch interaction {
        case .boxSelecting(let start, let current, _, _)?, .wireBoxSelecting(let start, let current, _, _)?:
            CanvasRect(corner: start, current)
        default:
            nil
        }
    }

    /// The wire whose lane in tie `id` lies nearest `point` (display canvas points): the one an ⌥-click on the band unties.
    func laneWire(of id: TieID, near point: Vector2, in routing: WireRouting) -> Endpoint? {
        routing.ties[id]?.lanes.min { (($0.value - point).length, $0.key) < (($1.value - point).length, $1.key) }?.key
    }
}
