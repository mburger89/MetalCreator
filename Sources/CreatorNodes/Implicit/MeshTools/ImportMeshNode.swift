import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// A mesh from a file (mesh import spec, the node): an STL or a 3MF (one mesh per build item) read as it is, welded by exact position, scaled by the file's units or the
/// ones chosen, and placed on `placement` (the file's origin goes to the plane's origin, its x and y along the plane's, its z up
/// from it). The file is the node's `NodeSetting.meshFile`, embedded or linked. The parse is kept by `ImportedMeshCache`, so moving
/// the placement or changing the units never reads the file again. A mesh with problems still imports; the node says what is wrong
/// and fixes nothing.
public enum ImportMeshNode: NodeDefinition {
    public static let typeID = "creator.importMesh"
    public static let displayName = "Import Mesh"
    public static let category = NodeCategory.mesh
    public static let inputs = [
        SocketSpec("placement", .plane, defaultValue: .plane(.xy)),
        SocketSpec("units", .integer, defaultValue: .integer(ImportUnits.fromFile.rawValue)),
    ]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "File", controls: [.meshFile(NodeSetting.meshFile)]),
        InspectorSection(title: "Placement", controls: [.planePicker("placement"), .segmented("units", options: ImportUnits.options)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard let reference = context.node.inputValues[NodeSetting.meshFile]?.fileReference else { throw MeshImportProblem.notChosen }
        guard let units = ImportUnits(rawValue: try inputs.integer("units")) else {
            throw NodeError.invalidValue("“units” must be From file, mm, cm, m or in.")
        }
        let plane = try inputs.plane("placement")
        guard plane.origin.isFinite, let normal = plane.normal.normalized,
              let across = (plane.xAxis - normal * plane.xAxis.dot(normal)).normalized
        else { throw NodeError.invalidValue("“placement” has no direction.") }
        let resolver = context.images
        let imported = try await ImportedMeshCache.shared.meshes(for: resolver.stamp(of: reference)) {
            try parse(resolver.meshFileBytes(of: reference))
        }
        let unit = Plane(origin: plane.origin, normal: normal, xAxis: across)
        var meshes: [Scalar] = [], warnings: [String] = []
        for file in imported {
            let made = try placed(file, on: unit, scale: units.millimetres ?? file.unit ?? 1, file: reference.fileName ?? "Embedded",
                                  isCancelled: { Task.isCancelled })
            meshes.append(.mesh(made.mesh))
            warnings += made.warnings  // the evaluator says a warning shared by meshes once
        }
        // One mesh is a single value, as an STL always was; several (a 3MF's build items) are a list.
        return meshes.count == 1 ? NodeOutputs(["mesh": meshes[0]], warnings: warnings)
            : NodeOutputs(lists: ["mesh": meshes], warnings: warnings)
    }

    /// The meshes a file of these bytes holds: a zip (`PK\u{3}\u{4}`, whatever the file is called) is a 3MF, anything else an STL.
    /// Synchronous, so no loop's locals live across an `await`.
    static func parse(_ data: Data) throws -> [ImportedMesh] {
        let read = data.starts(with: [0x50, 0x4B, 0x03, 0x04])
            ? try ThreeMFReader.read(data, isCancelled: { Task.isCancelled })
            : [try STLReader.read(data, isCancelled: { Task.isCancelled })]
        // Counted here, so the cache keeps the counts with the parse and an edit to the placement or units never sorts the edges again.
        return read.map { file in
            var counted = file
            counted.edgeCounts = EdgeCounts(file.mesh)
            return counted
        }
    }

    /// The imported mesh scaled by `scale` and moved onto `plane`, in `Double` and narrowed to `Float` once; a coordinate that is
    /// not finite then is `coordinatesOverflow`.
    private static func placed(_ imported: ImportedMesh, on plane: Plane, scale: Double,
                               file: String, isCancelled: () -> Bool) throws -> (mesh: TriangleMesh, warnings: [String]) {
        let source = imported.mesh
        let (across, up, normal) = (plane.xAxis, plane.yAxis, plane.normal)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(source.positions.count)
        var low = SIMD3<Double>(repeating: .infinity), high = SIMD3<Double>(repeating: -.infinity)
        for (index, p) in source.positions.enumerated() {
            if index % 64_000 == 0, isCancelled() { throw CancellationError() }
            let local = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)) * scale
            low = pointwiseMin(low, local)
            high = pointwiseMax(high, local)
            let world = plane.origin + across * local.x + up * local.y + normal * local.z
            let narrowed = SIMD3<Float>(Float(world.x), Float(world.y), Float(world.z))
            guard narrowed.x.isFinite, narrowed.y.isFinite, narrowed.z.isFinite else { throw MeshImportProblem.coordinatesOverflow }
            positions.append(narrowed)
        }
        let counts = imported.edgeCounts ?? EdgeCounts(source)
        let size = high - low
        let facts = [
            PayloadFact("Triangles", source.triangleCount.display),
            PayloadFact("Vertices", source.vertexCount.display),
            PayloadFact("Size", "\(size.x.display) × \(size.y.display) × \(size.z.display) mm"),
            PayloadFact("Closed", counts.isClosed ? "Yes" : "No"),
            PayloadFact("File", file),
        ]
        let mesh = TriangleMesh(positions: positions, triangles: source.triangles, resolution: 0, quality: .export, source: nil,
                                extraFacts: facts, creaseAngle: displayCreaseAngle)
        var found = warnings(open: counts.open, overfull: counts.overfull, flipped: counts.flipped,
                             dropped: imported.droppedTriangles, triangles: source.triangleCount)
        if imported.ignoredExtras { found.append(ThreeMFReader.ignoredExtrasWarning) }
        if imported.partsLeftOut { found.append(ThreeMFReader.partsLeftOutWarning) }
        return (mesh, found)
    }

    /// An edge between faces that turn more than this many degrees draws sharp, so a CAD part's edges look hard (mesh import spec, "The
    /// display: hard edges"); a scan or a sphere has no such edge and stays smooth.
    static let displayCreaseAngle = 30.0

    /// What is wrong with the mesh, in the words of the spec, each with its singular.
    static func warnings(open: Int, overfull: Int, flipped: Int, dropped: Int, triangles: Int) -> [String] {
        var found: [String] = []
        if open > 0 { found.append("This mesh isn't closed: \(open.display) open \(open == 1 ? "edge" : "edges").") }
        if overfull > 0 {
            let edges = overfull == 1 ? "edge" : "edges"
            found.append("This mesh has \(overfull.display) \(edges) shared by more than two faces.")
        }
        if flipped > 0 {
            let one = flipped == 1
            found.append("\(flipped.display) \(one ? "edge joins" : "edges join") faces flipped against each other.")
        }
        if dropped > 0 {
            found.append("\(dropped.display) degenerate \(dropped == 1 ? "triangle was" : "triangles were") dropped.")
        }
        if triangles > MeshImportLimits.warnTriangles {
            found.append("This mesh has \(triangles.display) triangles, so the view may be slow.")
        }
        return found
    }
}
