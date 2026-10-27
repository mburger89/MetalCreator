import CreatorGeometry
import CreatorGraph

/// The taut routes of a level's wires and the layouts of its ties (cable ties spec 2026-10-26 §5.1), from the socket anchors,
/// in display canvas points. Pure: `EditorModel.wireRouting` builds it from the level shown, and the tests build it from
/// anchors they choose.
public struct WireRouting: Equatable, Sendable {
    /// Each link's route, by its input endpoint.
    public var routes: [Endpoint: WireRoute]
    public var ties: [TieID: TieLayout]

    /// `outputs` and `inputs` are the anchors of the links' two ends; a link missing either is left out. A wire meets its
    /// ties in the order of their stored `position.x`, then by ID.
    public init(links: [Link], ties: [TieID: CableTie], outputs: [Endpoint: Vector2], inputs: [Endpoint: Vector2],
                flow: CanvasFlow) {
        let layouts = ties.mapValues { TieLayout($0, inputs: inputs, flow: flow) }
        var held: [Endpoint: [CableTie]] = [:]
        for tie in ties.values {
            for wire in tie.wires { held[wire, default: []].append(tie) }
        }
        var routes: [Endpoint: WireRoute] = [:]
        for link in links {
            guard let start = outputs[link.from], let end = inputs[link.to] else { continue }
            let lanes = (held[link.to] ?? []).sorted { ($0.position.x, $0.id) < ($1.position.x, $1.id) }
                .compactMap { layouts[$0.id]?.lanes[link.to] }
            routes[link.to] = WireRoute(wire: link.to, through: [start] + lanes + [end], flow: flow)
        }
        self.routes = routes
        self.ties = layouts
    }
}
