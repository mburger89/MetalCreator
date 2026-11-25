import CreatorGeometry
import CreatorKernel

/// Finds what a saved anchor stands for in the part as it is now (plan R4). It never asks `Topology.resolution`, whose operand
/// keys and nearest-count fallbacks guess.
public enum DrawingAnchorResolver {
    /// Edge ends this close (mm) meet; equal to the kernel's internal run-join tolerance (a test holds them equal).
    public static let joinTolerance = 1e-4
    /// Edges leaving a point within this many radians of opposite directions continue each other.
    public static let joinAngle = 0.01

    public static func resolve(_ target: AnchorTarget, in topology: Topology, frame: ProjectionFrame) -> AnchorResolution {
        switch target {
        case .edge(let pick):
            switch heldEdges(pick, in: topology) {
            case .failure(let reason): return .lost(reason)
            case .success(let held): return .held(geometry(of: held.edges), edges: held.edges.map(\.id), isRun: held.isRun)
            }
        case .corner(let first, let second): return corner(first, second, in: topology)
        case .centre(let pick): return centre(pick, in: topology, frame: frame)
        case .outline(let pick, let side): return cylinder(pick, side: side, in: topology, frame: frame)
        case .axis(let pick): return cylinder(pick, side: nil, in: topology, frame: frame)
        case .point: return .lost(.missing)
        }
    }

    private static func centre(_ pick: EdgePick, in topology: Topology, frame: ProjectionFrame) -> AnchorResolution {
        let found = heldEdges(pick, in: topology)
        guard case .success(let held) = found else { return lost(found) }
        guard case .circle(let center, let axis, _, _) = geometry(of: held.edges) else { return .lost(.notLineOrCircle) }
        // R5: a centre obeys the circle rule, so a hole a model edit tilts loses its centre dimension.
        guard abs(axis.dot(frame.direction)) >= 1 - 1e-9 else { return .lost(.foreshortened) }
        return .held(.point(center), edges: held.edges.map(\.id), isRun: held.isRun)
    }

    private struct Held {
        var edges: [EdgeInfo]
        var isRun: Bool
    }

    private static func lost(_ result: Result<Held, LostReason>) -> AnchorResolution {
        if case .failure(let reason) = result { return .lost(reason) }
        return .lost(.missing)
    }

    private static func heldEdges(_ pick: EdgePick, in topology: Topology) -> Result<Held, LostReason> {
        let matches = topology.edges(matching: pick.key)
        if !matches.isEmpty { return classify(matches, expectedRuns: pick.runCount ?? pick.matchCount) }
        guard let narrowed = pick.key.narrowed else { return .failure(.missing) }
        let found = topology.edges(matching: narrowed)
        guard !found.isEmpty else { return .failure(.missing) }
        // A narrowed key must find exactly one edge.
        if found.count == 1 { return .success(Held(edges: found, isRun: false)) }
        let runs = Topology.runCount(found)
        return .failure(.several(runs > 1 ? runs : found.count))
    }

    private static func classify(_ matches: [EdgeInfo], expectedRuns: Int) -> Result<Held, LostReason> {
        if matches.count == 1 { return .success(Held(edges: matches, isRun: false)) }
        let runs = Topology.runCount(matches)
        if runs == 1 && expectedRuns == 1 { return .success(Held(edges: matches, isRun: true)) }
        return .failure(.several(runs > 1 ? runs : matches.count))
    }

    private static func geometry(of edges: [EdgeInfo]) -> AnchorGeometry {
        let curves = edges.compactMap(\.curve)
        guard curves.count == edges.count, let first = curves.first else {
            return .other(midpoint: edges.first?.midpoint ?? Vector3(0, 0, 0))
        }
        switch first {
        case .line:
            let lines = curves.filter { if case .line = $0 { true } else { false } }
            guard lines.count == curves.count else { return .other(midpoint: edges[0].midpoint) }
            if curves.count == 1, case .line(let start, let end) = first { return .segment(start, end) }
            let ends = runEnds(of: edges)
            guard ends.count == 2 else { return .other(midpoint: edges[0].midpoint) }
            return .segment(ends[0], ends[1])
        case .circle(let center, let axis, let radius, _, _):
            var sweep = 0.0
            for curve in curves {
                guard case .circle(_, _, _, _, let part) = curve else { return .other(midpoint: edges[0].midpoint) }
                sweep += part
            }
            return .circle(center: center, axis: axis.normalized ?? axis, radius: radius, sweep: sweep)
        }
    }

    /// The ends of a run that no other piece of the run meets (a run's two extreme ends; none for a closed run or a full circle).
    private static func runEnds(of edges: [EdgeInfo]) -> [Vector3] {
        var all: [(piece: Int, point: Vector3)] = []
        for (index, edge) in edges.enumerated() {
            for point in edge.curve?.ends ?? [] { all.append((index, point)) }
        }
        return all.filter { candidate in
            !all.contains { $0.piece != candidate.piece && ($0.point - candidate.point).length <= joinTolerance }
        }.map(\.point)
    }

    private static func corner(_ first: EdgePick, _ second: EdgePick, in topology: Topology) -> AnchorResolution {
        let a: Held
        let b: Held
        switch (heldEdges(first, in: topology), heldEdges(second, in: topology)) {
        case (.failure(let reason), _), (_, .failure(let reason)): return .lost(reason)
        case (.success(let x), .success(let y)): (a, b) = (x, y)
        }
        let meeting = runEnds(of: a.edges).filter { p in
            runEnds(of: b.edges).contains { (p - $0).length <= joinTolerance }
        }
        guard meeting.count == 1 else { return .lost(.cornerGone) }
        return .held(.point(meeting[0]), edges: (a.edges + b.edges).map(\.id), isRun: a.isRun || b.isRun)
    }

    private static func cylinder(_ pick: FacePick, side: Vector2?, in topology: Topology, frame: ProjectionFrame) -> AnchorResolution {
        let faces = topology.faces(matching: pick)
        guard !faces.isEmpty else { return .lost(.missing) }
        guard faces.count == 1 else { return .lost(.severalFaces(faces.count)) }
        let face = faces[0]
        guard face.kind == .cylinder, let radius = face.radius, let axisPoint = face.axisPoint, let axis = face.normal?.normalized else {
            return .lost(.notCylinder)
        }
        guard let side else {
            return .held(.cylinder(axisPoint: axisPoint, axis: axis, radius: radius, side: 0), edges: [], isRun: false)
        }
        // The axis on the sheet turned +90 degrees points from the axis to the outline of side +1 (axis x viewDirection).
        let flat = frame.place(axis)
        guard flat.length > 1e-9 else { return .lost(.outlineTurned) }
        let turned = Vector2(-flat.y / flat.length, flat.x / flat.length)
        let along = turned.x * side.x + turned.y * side.y
        guard abs(along) >= 0.5 else { return .lost(.outlineTurned) }
        return .held(
            .cylinder(axisPoint: axisPoint, axis: axis, radius: radius, side: along > 0 ? 1 : -1), edges: [], isRun: false)
    }
}
