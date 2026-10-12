import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

/// What a selected layout node draws in the viewport (patterns spec §8): its placements as small axis triads (x, y and z in
/// the theme's axis colours), and for Face Pattern the outline of the area it fills, dashed. It is an overlay, drawn over the
/// scene like the sketch editor's lines, so it never picks, frames the view or opens a menu (it is no part of the model).
public enum LayoutPreview {
    /// The nodes whose placements are previewed.
    public static let layoutTypes: Set<String> = [
        LinearPatternNode.typeID, GridPatternNode.typeID, CircularPatternNode.typeID, CurvePatternNode.typeID, FacePatternNode.typeID,
    ]

    /// How long a triad's axes are when there is a single placement, in millimetres.
    static let singleTriad = 5.0
    /// A triad's axes are this much of the distance between neighbouring placements, so triads never touch.
    static let triadShare = 0.4

    /// The overlay for `node`: its `placements` output as triads, with Face Pattern's clipped area. Empty for any other node,
    /// for one that has no good result, and for one with no placements.
    public static func overlay(for node: Node, graph: Graph, results: [NodeID: NodeResult]) -> ViewportOverlay {
        guard layoutTypes.contains(node.typeID), let result = results[node.id], result.state.isSuccess,
              let value = result.outputs?["placements"] else { return ViewportOverlay() }
        let planes = value.items.compactMap { scalar -> Plane? in
            if case .plane(let plane) = scalar { plane } else { nil }
        }
        var overlay = ViewportOverlay(lines: triads(of: planes))
        if node.typeID == FacePatternNode.typeID {
            overlay.lines += clippedArea(of: node, graph: graph, results: results)
        }
        return overlay
    }

    /// An x, y and z line for each placement.
    static func triads(of planes: [Plane]) -> [OverlayLine] {
        let length = triadLength(of: planes)
        return planes.flatMap { plane in
            [OverlayLine(plane.origin, plane.origin + plane.xAxis * length, tint: .axisX),
             OverlayLine(plane.origin, plane.origin + plane.yAxis * length, tint: .axisY),
             OverlayLine(plane.origin, plane.origin + plane.normal * length, tint: .axisZ),
            ]
        }
    }

    /// `singleTriad` for one placement (or placements all in one place), else `triadShare` of the smallest distance between
    /// placements that follow each other.
    static func triadLength(of planes: [Plane]) -> Double {
        let steps = zip(planes, planes.dropFirst()).map { ($1.origin - $0.origin).length }.filter { $0 > 1e-9 }
        guard let nearest = steps.min() else { return singleTriad }
        return nearest * triadShare
    }

    /// The dashed outline of the area a Face Pattern fills: its solid and margin read the way the node reads them (from the
    /// wire, else the typed value), its face the node's pick.
    static func clippedArea(of node: Node, graph: Graph, results: [NodeID: NodeResult]) -> [OverlayLine] {
        guard case .facePick(let pick)? = node.inputValues[NodeSetting.face],
              case .solid(let solid)? = input("solid", of: node, graph: graph, results: results)?.items.first else { return [] }
        var margin = 0.0
        if case .number(let value)? = input("margin", of: node, graph: graph, results: results)?.items.first { margin = value }
        return FacePatternNode.clippedArea(of: solid, pick: pick, margin: margin).flatMap { loop in
            loop.indices.map { index in
                OverlayLine(loop[index], loop[(index + 1) % loop.count], tint: .construction, isDashed: true)
            }
        }
    }

    /// The value on `socket` of `node`: what the wire into it carries, else its typed value converted as the evaluator would.
    private static func input(_ socket: SocketName, of node: Node, graph: Graph, results: [NodeID: NodeResult]) -> Value? {
        if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)) {
            return results[link.from.node]?.outputs?[link.from.socket]
        }
        let spec = FacePatternNode.inputs.first { $0.name == socket }
        guard let constant = node.inputValues[socket] ?? spec?.defaultValue, let type = spec?.type else { return nil }
        return Scalar(constant)?.converted(to: type).map(Value.one)
    }
}
