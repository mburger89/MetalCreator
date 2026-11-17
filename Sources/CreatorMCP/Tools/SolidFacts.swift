import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// What a client needs to know about a solid without a second tool: its face and edge counts and its bounds (stored mm).
public struct SolidFacts: Equatable, Sendable {
    public var faces: Int
    public var edges: Int
    public var min: Vector3
    public var max: Vector3
    /// "solid", "sheet" or "solid and sheet": what the faces and edges make.
    public var kind: String
    public var openEdges: Int

    public init(_ solid: Solid) {
        faces = solid.topology.faces.count
        edges = solid.topology.edges.count
        min = solid.bounds.min
        max = solid.bounds.max
        openEdges = solid.topology.edges.filter(\.isBoundary).count
        let onOpen = solid.topology.faces.filter(\.isOnOpenShell).count
        if onOpen == 0 {
            kind = "solid"
        } else if onOpen == solid.topology.faces.count {
            kind = "sheet"
        } else {
            kind = "solid and sheet"
        }
    }

    private var hasBounds: Bool { min.x <= max.x && min.y <= max.y && min.z <= max.z }

    private static func point(_ vector: Vector3) -> String {
        "(" + [vector.x, vector.y, vector.z].map(ValueSummary.format).joined(separator: ", ") + ")"
    }

    /// "solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm"
    public var text: String {
        let counts = "\(faces) \(faces == 1 ? "face" : "faces"), \(edges) \(edges == 1 ? "edge" : "edges")"
        let bounds = hasBounds ? "bounds \(Self.point(min)) to \(Self.point(max)) mm" : "no bounds"
        if kind == "solid" { return "solid: \(counts), \(bounds)" }
        let open = "\(openEdges) open \(openEdges == 1 ? "edge" : "edges")"
        return "\(kind): \(faces) \(faces == 1 ? "face" : "faces"), \(open), \(bounds)"
    }

    @MainActor public var json: JSONValue {
        func triple(_ vector: Vector3) -> JSONValue {
            .array([ReadTools.number(vector.x), ReadTools.number(vector.y), ReadTools.number(vector.z)])
        }
        return .object([
            "kind": .string(kind), "faces": .int(faces), "edges": .int(edges), "bounds_min": triple(min), "bounds_max": triple(max),
        ])
    }
}
