import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

/// Turns the selected nodes' `HandleSpec`s into viewport handles (spec §6.5), resolved against their inputs'
/// results. A handle is shown only for an unwired number input (a wired one would be overwritten by its wire, as
/// the inspector shows it read-only), and not while the node's `NodeSetting.showHandle` reads `.bool(false)`
/// (missing counts as shown, as the inspector's toggle reads it).
/// - `.linear(socket)` follows Extrude's convention: the arrow starts at the centre of the profile wired into
///   `profile` and points along its plane's normal, reversed by a true `reversed`; a symmetric `mode` (1) gives it
///   `scale` 0.5, so the knob sits on the far cap, half the distance out, and follows the pointer.
/// - `.radial(socket)` sits at the midpoint of the first edge of the set wired into `edges`, pointing out along the
///   bisector of its two faces' normals.
public enum HandleBuilder {
    public static func handles(for selection: Set<NodeID>, graph: Graph, results: [NodeID: NodeResult],
                               registry: NodeRegistry) -> [ResolvedHandle] {
        selection.sorted().flatMap { id -> [ResolvedHandle] in
            guard let node = graph.nodes[id], let definition = registry[node.typeID],
                  node.inputValues[NodeSetting.showHandle] != .bool(false) else { return [] }
            return definition.handles.compactMap { spec in
                resolve(spec, node: node, definition: definition, graph: graph, results: results)
            }
        }
    }

    static func resolve(_ spec: HandleSpec, node: Node, definition: any NodeDefinition.Type, graph: Graph,
                        results: [NodeID: NodeResult]) -> ResolvedHandle? {
        let socket: SocketName
        switch spec {
        case .linear(let name), .radial(let name): socket = name
        }
        guard graph.incomingLink(to: Endpoint(node: node.id, socket: socket)) == nil,
              let input = definition.inputs.first(where: { $0.name == socket }), input.type == .number,
              let value = number(node.inputValues[socket] ?? input.defaultValue) else { return nil }
        let placement: Placement?
        let style: HandleStyle
        switch spec {
        case .linear:
            placement = linearPlacement(node, graph: graph, results: results)
            style = .linear
        case .radial:
            placement = radialPlacement(node, graph: graph, results: results)
            style = .radial
        }
        guard let placement else { return nil }
        let target = HandleTarget(node: node.id, socket: socket)
        let handle = ViewportHandle(id: target.handleID, anchor: placement.anchor, direction: placement.direction,
                                    value: value, range: input.range ?? 0...1_000, style: style,
                                    tint: definition.category == .feature ? .feature : .solid, scale: placement.scale)
        return ResolvedHandle(target: target, handle: handle)
    }

    /// Where a handle starts, which way it points, and its knob's millimetres per unit of value.
    typealias Placement = (anchor: Vector3, direction: Vector3, scale: Double)

    static func linearPlacement(_ node: Node, graph: Graph, results: [NodeID: NodeResult]) -> Placement? {
        guard case .profile(let profile)? = upstream(node, "profile", graph: graph, results: results),
              let centre = profile.bounds?.center else { return nil }
        let normal = profile.plane.normal.normalized ?? .unitZ
        if case .integer(1)? = node.inputValues["mode"] {
            return (centre, normal, 0.5)
        }
        let reversed = node.inputValues["reversed"] == .bool(true)
        return (centre, reversed ? -normal : normal, 1)
    }

    static func radialPlacement(_ node: Node, graph: Graph, results: [NodeID: NodeResult]) -> Placement? {
        guard case .edgeSet(let set)? = upstream(node, "edges", graph: graph, results: results),
              let edge = set.edges.first.flatMap(set.solid.topology.edge) else { return nil }
        let normals = edge.faces.compactMap { set.solid.topology.face($0)?.normal }
        guard let bisector = normals.reduce(Vector3.zero, +).normalized else { return nil }
        return (edge.midpoint, bisector, 1)
    }

    /// The first item the link into `node.socket` carries, from its upstream node's current result.
    static func upstream(_ node: Node, _ socket: SocketName, graph: Graph, results: [NodeID: NodeResult]) -> Scalar? {
        guard let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)),
              let result = results[link.from.node], result.state.isSuccess else { return nil }
        return result.outputs?[link.from.socket]?.items.first
    }

    static func number(_ value: ConstantValue?) -> Double? {
        switch value {
        case .number(let number)?: number
        case .integer(let integer)?: Double(integer)
        default: nil
        }
    }
}
