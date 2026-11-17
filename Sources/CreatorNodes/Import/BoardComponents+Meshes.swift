import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorPCB
import Foundation

extension ModelFormat {
    /// Formats that become a mesh on `component meshes` (the rest become solids).
    var isMesh: Bool { self == .vrml || self == .vrmlGzip || self == .x3d }
}

extension ModelTags {
    /// `solid` with every face named as a read model's: this node's tag and `.imported(face: i)` by the face's index.
    static func imported(_ solid: Solid, tag: NodeTag) -> Solid {
        var topology = solid.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = [TopoTag(tag, .imported(face: index))]
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: solid.storage)
    }
}

extension ModelFiles {
    /// An IDF outline extruded by its height and named like a read STEP solid.
    static func readOutline(_ source: Source, stamp: ImageStamp, kernel: any Kernel,
                            tag: NodeTag) async throws -> ComponentModelCache.Made {
        let file = try bytes(of: source, format: .idf, stamp: stamp)
        guard ModelFormat.idf.matches(file.data) else { throw ModelProblem("the file isn't an IDF model", isRemembered: true) }
        let outline = try idfOutline(file.data)
        do {
            let solid = try await kernel.extrude(outline.profile, distance: outline.height, mode: .oneSided, tag: tag)
            return ComponentModelCache.Made(solid: ModelTags.imported(solid, tag: tag), isCurrent: file.isCurrent)
        } catch let error as KernelError {
            throw problem(from: error)
        }
    }

    private static func idfOutline(_ data: Data) throws -> IDFOutline {
        do {
            return try IDFReader.read(data, isCancelled: { Task.isCancelled })
        } catch let problem as KiCadProblem {
            throw ModelProblem(readerReason(problem.message), isRemembered: true)
        }
    }

    /// A VRML, compressed VRML or X3D model's mesh, in the file's units. Synchronous, so no loop's locals live across an `await`.
    static func readMesh(_ source: Source, format: ModelFormat, stamp: ImageStamp) throws -> ComponentModelCache.MadeMesh {
        let file = try bytes(of: source, format: format, stamp: stamp)
        var bytes = file.data
        let word = format == .x3d ? "X3D" : "VRML"
        guard format.matches(bytes) else { throw ModelProblem("the file isn't a \(word) model", isRemembered: true) }
        if format == .vrmlGzip {
            bytes = try gunzipped(bytes, limit: VRMLReader.maximumBytes)
            guard ModelFormat.vrml.matches(bytes) else { throw ModelProblem("the file isn't a VRML model", isRemembered: true) }
        }
        do {
            let model = format == .x3d
                ? try X3DReader.read(bytes, isCancelled: { Task.isCancelled })
                : try VRMLReader.read(bytes, isCancelled: { Task.isCancelled })
            return ComponentModelCache.MadeMesh(model: model, isCurrent: file.isCurrent)
        } catch let error as MeshImportProblem {
            throw ModelProblem(meshReason(error), isRemembered: true)
        }
    }

    /// A reader's sentence as the phrase in parentheses: "This VRML file uses a shape before it is defined." becomes
    /// "it uses a shape before it is defined"; any other sentence is lower-cased and its period dropped.
    static func readerReason(_ sentence: String) -> String {
        switch sentence {
        case "This file isn't a VRML 1 or VRML 2 file.": return "the file isn't a VRML model"
        case "This file isn't an X3D file.": return "the file isn't an X3D model"
        default: break
        }
        let stored = "The stored model "
        if sentence.hasPrefix(stored) {
            // "The stored model is damaged." and "... is larger than 256 MB." become "it is ..."; the dictionary one is shortened.
            if sentence.hasPrefix(stored + "uses a zstd dictionary") { return "it uses a zstd dictionary" }
            var rest = String(sentence.dropFirst(stored.count))
            if rest.hasSuffix(".") { rest.removeLast() }
            return "it " + rest
        }
        for format in ["VRML", "X3D", "IDF"] {
            let starts = [("This \(format) file ", "it "), ("This \(format) file's ", "its ")]
            for (prefix, subject) in starts where sentence.hasPrefix(prefix) {
                var rest = String(sentence.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if rest.hasSuffix(".") { rest.removeLast() }
                return subject + rest
            }
        }
        return reason(from: sentence)
    }

    /// What a mesh reader's refusal says, in KiCad's words.
    static func meshReason(_ problem: MeshImportProblem) -> String {
        switch problem {
        case .tooManyTriangles, .overTriangleLimit:
            "it has more than \(MeshImportLimits.maxTriangles.display) triangles"
        case .noTriangles: "it has no triangles"
        case .tooLarge, .modelTooLarge: "it is larger than \(VRMLReader.maximumBytes >> 20) MB"
        case .coordinatesOverflow: "its coordinates are too large"
        case .malformedModel(let reason):
            // The XML scanner's own wording ("it stops inside a tag.") with the final period dropped.
            reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        default: readerReason(problem.message)
        }
    }
}

/// One VRML or X3D model of a footprint, scaled and placed in the world.
struct MeshPiece {
    var footprint: Int
    var name: String
    var positions: [SIMD3<Float>]
    var triangles: [UInt32]
}

extension Placer {
    /// The mesh of one model path: read once (kept in file units) or the reason it can't be.
    func loadMesh(_ source: ModelFiles.Source, name: String, format: ModelFormat, stamp: ImageStamp) async throws -> BoardComponents.Found {
        let key = ComponentModelCache.ReadKey(stamp: stamp, format: format)
        do {
            let made = try await cache.mesh(for: key) {
                try ModelFiles.readMesh(source, format: format, stamp: stamp)
            }
            return .mesh(made.model, name: name)
        } catch let problem as ModelProblem {
            return .unreadable(name: name, reason: problem.reason)
        }
    }

    /// Whether the model is read as a mesh.
    func isMesh(_ model: ModelReference, of index: Int) -> Bool {
        if case .mesh = found[BoardComponents.foundKey(model.path, of: setting.board.footprints[index])] { return true }
        return false
    }

    /// Decides, before any point is moved, whether this footprint's meshes are made: the triangles its placeable models hold
    /// are counted from the cached meshes, a footprint over the per-footprint limit is left out and named, and once the board's
    /// budget is spent so is every footprint after it (counted in one warning).
    mutating func admitMeshes(of models: [ModelReference], footprint index: Int) -> Bool {
        var triangles = 0
        for model in models {
            guard case .mesh(let found, _) = found[BoardComponents.foundKey(model.path, of: setting.board.footprints[index])],
                  [model.scale.x, model.scale.y, model.scale.z].allSatisfy({ $0.isFinite && $0 > 0 }) else { continue }
            triangles += found.mesh.positions.isEmpty ? 0 : found.mesh.triangles.count / 3
        }
        guard triangles > 0 else { return true }
        let limits = BoardComponents.meshLimits
        if triangles > limits.footprint {
            let reference = setting.board.footprints[index].reference
            problems.meshesOverFootprintLimit.append(reference.isEmpty ? "unnamed" : reference)
            leftOut.insert(index)
            return false
        }
        if meshBudgetSpent || meshTriangles + triangles > limits.board {
            meshBudgetSpent = true
            problems.meshesLeftOut += 1
            leftOut.insert(index)
            return false
        }
        meshTriangles += triangles
        return true
    }

    /// The model's mesh scaled (and converted from the file's units), moved by the model's frame and the board's; nil (the
    /// problem noted) when it can't be, and nil without a problem when the file held nothing to draw. Only called for a footprint
    /// `admitMeshes` allowed, so a budget is never spent on points that are then thrown away.
    mutating func placeMesh(_ found: ImportedModelMesh, scale: Vector3, of index: Int, plane: Plane, name: String) throws -> MeshPiece? {
        if found.skippedGeometry { problems.skipped.append(name) }
        if found.referencesFiles { problems.inlined.append(name) }
        guard !found.mesh.positions.isEmpty, !found.mesh.triangles.isEmpty else { return nil }
        BoardComponents.meshMoveObserver?(found.mesh.positions.count)
        let unit = found.isMillimetres ? 1 : 2.54
        let factors = Vector3(scale.x * unit, scale.y * unit, scale.z * unit)
        guard let positions = try Self.moved(found.mesh.positions, by: factors, onto: plane) else {
            problems.unreadable.append("\(name) (its coordinates are too large)")
            return nil
        }
        return MeshPiece(footprint: index, name: name, positions: positions, triangles: found.mesh.triangles)
    }

    /// Each point scaled by `factors`, then carried from the plane's local frame to the world, in `Double`, narrowed to `Float` once;
    /// nil when a coordinate isn't finite then.
    private static func moved(_ points: [SIMD3<Float>], by factors: Vector3, onto plane: Plane) throws -> [SIMD3<Float>]? {
        let (across, up, normal) = (plane.xAxis, plane.yAxis, plane.normal)
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            if index % 65_536 == 0, Task.isCancelled { throw CancellationError() }
            let local = Vector3(Double(point.x) * factors.x, Double(point.y) * factors.y, Double(point.z) * factors.z)
            let world = plane.origin + across * local.x + up * local.y + normal * local.z
            let narrowed = SIMD3<Float>(Float(world.x), Float(world.y), Float(world.z))
            guard narrowed.x.isFinite, narrowed.y.isFinite, narrowed.z.isFinite else { return nil }
            result.append(narrowed)
        }
        return result
    }
}

/// The most triangles a footprint's joined mesh, and all of a board's `component meshes`, may hold (injectable for tests).
struct MeshLimits: Sendable {
    var footprint = MeshImportLimits.maxTriangles
    var board = 20_000_000
}

extension BoardComponents {
    @TaskLocal static var meshLimits = MeshLimits()
    /// Called with a model's point count each time its points are moved (a test counts them).
    @TaskLocal static var meshMoveObserver: (@Sendable (Int) -> Void)?

    /// A footprint's pieces joined into one mesh each, in the order of the pieces (R2: vertices are not welded across models). The
    /// budgets were applied before any point was moved (`Placer.admitMeshes`), so this only concatenates, and empties each
    /// footprint's pieces as it joins them.
    static func joined(_ pieces: inout [MeshPiece], board: KiCadBoard,
                       problems: inout Problems) throws -> [(footprint: Int, mesh: TriangleMesh)] {
        var meshes: [(footprint: Int, mesh: TriangleMesh)] = []
        var start = 0
        while start < pieces.count {
            try Task.checkCancellation()
            var end = start + 1
            while end < pieces.count, pieces[end].footprint == pieces[start].footprint { end += 1 }
            let footprintIndex = pieces[start].footprint
            let footprint = board.footprints[footprintIndex]
            let vertices = pieces[start..<end].reduce(0) { $0 + $1.positions.count }
            if vertices > Int(UInt32.max) {
                let names = pieces[start..<end].map(\.name).joined(separator: " and ")
                problems.unreadable.append("\(names) (they have too many points to join)")
            } else {
                var positions: [SIMD3<Float>] = []
                var indices: [UInt32] = []
                positions.reserveCapacity(vertices)
                for index in start..<end {
                    if index > start { try Task.checkCancellation() }
                    let offset = UInt32(positions.count)
                    positions += pieces[index].positions
                    indices += pieces[index].triangles.map { $0 + offset }
                    pieces[index].positions = []
                    pieces[index].triangles = []
                }
                meshes.append((footprintIndex, mesh(positions, indices, footprint: footprint)))
            }
            start = end
        }
        return meshes
    }
    private static func mesh(_ positions: [SIMD3<Float>], _ triangles: [UInt32], footprint: Footprint) -> TriangleMesh {
        var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
        for point in positions {
            low = pointwiseMin(low, point)
            high = pointwiseMax(high, point)
        }
        let size = high - low
        let facts = [
            PayloadFact("Component", footprint.reference.isEmpty ? "unnamed" : footprint.reference),
            PayloadFact("Triangles", (triangles.count / 3).display),
            PayloadFact("Vertices", positions.count.display),
            PayloadFact("Size", "\(Double(size.x).display) × \(Double(size.y).display) × \(Double(size.z).display) mm"),
        ]
        return TriangleMesh(positions: positions, triangles: triangles, resolution: 0, quality: .export, source: nil,
                            extraFacts: facts, creaseAngle: ImportMeshNode.displayCreaseAngle)
    }
}
