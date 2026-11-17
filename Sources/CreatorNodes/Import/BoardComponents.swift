import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorPCB
import Foundation

/// The components of an imported board (KiCad import spec, Components): one solid per footprint, made of its STEP, compressed STEP,
/// IGES or IDF models, and one mesh per footprint, made of its VRML, compressed VRML or X3D models; each read once, scaled once per
/// distinct scale and placed as KiCad places it.
enum BoardComponents {
    static let maxDistinctModels = 10_000
    static let maxModelBytes = 256 << 20
    static let listedNames = 8

    /// What a board's components came to.
    struct Outcome {
        var solids: [Solid] = []
        /// One mesh per footprint with a VRML or X3D model, in natural reference order.
        var meshes: [TriangleMesh] = []
        /// How many footprints have a solid, a mesh or both.
        var withModel = 0
        var warnings: [String] = []
        var dependencies: [FileDependency] = []
        /// Footprints whose models are all hidden: skipped, neither warned about nor counted as without a model.
        var hiddenOnly = 0
    }

    /// Where the node stands: the board in its own frame, and the world frame it is placed in.
    struct Setting {
        var board: KiCadBoard
        var origin: Vector2
        var thickness: Double
        var frame: Plane
        var folder: String
    }

    /// Where path variables come from: the process environment and KiCad's settings folders under the home folder. The tests
    /// replace it with an empty environment and a temporary home.
    struct Environment: Sendable {
        var variables: [String: String]
        var home: String
        static let real = Environment(variables: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
    }

    @TaskLocal static var environment = Environment.real

    /// What one distinct model path came to.
    enum Found {
        case notFound
        case unreadable(name: String, reason: String)
        case solid(Solid, ComponentModelCache.ReadKey, name: String, isCurrent: Bool)
        case mesh(ImportedModelMesh, name: String)
    }

    /// One model of a footprint, placed.
    struct Piece {
        var footprint: Int
        var name: String
        var tool: Solid
        var plane: Plane
    }

    static func build(_ setting: Setting, kernel: any Kernel, context: EvalContext,
                      cache: ComponentModelCache = .shared) async throws -> Outcome {
        let order = naturalOrder(setting.board)
        let visible = setting.board.footprints.map { $0.models.filter { !$0.isHidden } }
        let paths = distinctPaths(order: order, visible: visible)
        guard paths.count <= maxDistinctModels else {
            throw NodeError.invalidValue("This board names more than 10,000 different 3D models.")
        }
        var outcome = Outcome()
        let settings = KiCadSettingsFiles.read(environment: environment.variables, home: environment.home)
        outcome.dependencies = settings.dependencies
        let variables = KiCadPathVariables.merged(environment: environment.variables,
                                                  settings: settings.variables, platform: .current)
        var placer = Placer(setting: setting, kernel: kernel, cache: cache, node: context.node.id)
        for path in paths {
            try Task.checkCancellation()
            let resolved = ModelFiles.resolve(path, folder: setting.folder, variables: variables)
            outcome.dependencies += resolved.dependencies
            placer.found[path] = try await placer.load(resolved.result)
        }
        var pieces: [Piece] = []
        var meshPieces: [MeshPiece] = []
        for index in order {
            try Task.checkCancellation()
            guard !visible[index].isEmpty else {
                if setting.board.footprints[index].models.isEmpty {
                    let name = setting.board.footprints[index].reference
                    placer.problems.noModel.append(name.isEmpty ? "unnamed" : name)
                } else {
                    outcome.hiddenOnly += 1
                }
                continue
            }
            let meshesAllowed = placer.admitMeshes(of: visible[index], footprint: index)
            for model in visible[index] {
                if !meshesAllowed, placer.isMesh(model) { continue }
                switch try await placer.place(model, of: index) {
                case .solid(let piece): pieces.append(piece)
                case .mesh(let piece): meshPieces.append(piece)
                case nil: break
                }
            }
        }
        let made = try await assemble(pieces, setting: setting, kernel: kernel, context: context, problems: &placer.problems)
        let joined = try joined(&meshPieces, board: setting.board, problems: &placer.problems)
        outcome.solids = made.map(\.solid)
        outcome.meshes = joined.map(\.mesh)
        // A footprint whose meshes a budget left out has a model: it is not one "without a 3D model".
        outcome.withModel = Set(made.map(\.footprint)).union(joined.map(\.footprint)).union(placer.leftOut).count
        outcome.warnings = placer.problems.sentences()
        return outcome
    }

    /// Each non-hidden model path once, in the order the footprints (in natural order) first name it.
    private static func distinctPaths(order: [Int], visible: [[ModelReference]]) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        for index in order {
            for model in visible[index] where seen.insert(model.path).inserted { paths.append(model.path) }
        }
        return paths
    }

    /// Footprints by reference in natural order ("C2" before "C10"), ties in file order.
    static func naturalOrder(_ board: KiCadBoard) -> [Int] {
        board.footprints.indices.sorted { lhs, rhs in
            let (a, b) = (board.footprints[lhs].reference, board.footprints[rhs].reference)
            if a != b { return BoardHoles.naturallyOrdered(a, before: b) }
            return lhs < rhs
        }
    }

    struct ScaleID: Hashable {
        var key: ComponentModelCache.ReadKey
        var scale: Vector3
    }

    /// A folder path as the platform's file calls want it: Windows URLs give "/C:/b", which drops its leading slash.
    static func normalisedFolder(_ path: String) -> String {
        let chars = Array(path)
        guard chars.count >= 3, chars[0] == "/", chars[1].isLetter, chars[2] == ":",
              chars.count == 3 || chars[3] == "/" || chars[3] == "\\" else { return path }
        return String(path.dropFirst())
    }

    /// The model's frame (board-local, y up) as a plane in the world: the board frame's origin, axes and normal carry it.
    static func worldPlane(_ model: ModelFrame, in board: Plane) -> Plane? {
        func point(_ p: Vector3) -> Vector3 { board.origin + board.xAxis * p.x + board.yAxis * p.y + board.normal * p.z }
        func direction(_ v: Vector3) -> Vector3 { board.xAxis * v.x + board.yAxis * v.y + board.normal * v.z }
        let origin = point(model.origin)
        let (normal, across) = (direction(model.zAxis), direction(model.xAxis))
        guard origin.isFinite, normal.isFinite, across.isFinite else { return nil }
        return Plane(origin: origin, normal: normal, xAxis: across)
    }

    /// Every piece placed in one kernel call, then each footprint's pieces made one solid.
    private static func assemble(_ pieces: [Piece], setting: Setting, kernel: any Kernel, context: EvalContext,
                                 problems: inout Problems) async throws -> [(footprint: Int, solid: Solid)] {
        guard !pieces.isEmpty else { return [] }
        let items = pieces.map { KiCadKey.item(for: setting.board.footprints[$0.footprint].identity) }
        let placed = try await PlacementMoves.place(pieces.map(\.tool), planes: pieces.map(\.plane), items: items,
                                                    placedBy: context.node.id, kernel: kernel,
                                                    tag: NodeTag(node: context.node.id, item: 0))
        var solids: [(footprint: Int, solid: Solid)] = []
        var start = 0
        while start < pieces.count {
            var end = start + 1
            while end < pieces.count, pieces[end].footprint == pieces[start].footprint { end += 1 }
            if end - start == 1 {
                solids.append((pieces[start].footprint, placed[start]))
            } else {
                let parts = (start..<end).map { retagged(placed[$0], model: $0 - start) }
                do {
                    let joined = try await kernel.compound(parts, tag: NodeTag(node: context.node.id, item: items[start]))
                    solids.append((pieces[start].footprint, joined))
                } catch let error as KernelError {
                    let names = pieces[start..<end].map(\.name).joined(separator: " and ")
                    problems.unreadable.append("\(names) (\(ModelFiles.reason(from: error.userMessage)))")
                }
            }
            start = end
        }
        return solids
    }

    /// The k-th model of a footprint names its faces `(k << 32) + i`, so two models never share a name (ruling R1).
    static func retagged(_ solid: Solid, model k: Int) -> Solid {
        guard k > 0 else { return solid }
        return ModelTags.rewritten(solid) { tag in
            guard case .imported(let face) = tag.role else { return tag }
            return TopoTag(node: tag.node, item: tag.item, role: .imported(face: (k << 32) + face))
        }
    }
}

/// What reading and placing the models of one board needs and has found so far.
struct Placer {
    var setting: BoardComponents.Setting
    var kernel: any Kernel
    var cache: ComponentModelCache
    var node: NodeID
    var found: [String: BoardComponents.Found] = [:]
    var problems = Problems()
    var memo: [BoardComponents.ScaleID: Solid] = [:]
    /// Triangles of the meshes admitted so far on this board, and whether the board's budget has been spent.
    var meshTriangles = 0
    var meshBudgetSpent = false
    /// Footprints whose meshes a budget left out.
    var leftOut: Set<Int> = []

    init(setting: BoardComponents.Setting, kernel: any Kernel, cache: ComponentModelCache, node: NodeID) {
        self.setting = setting
        self.kernel = kernel
        self.cache = cache
        self.node = node
    }

    func load(_ result: ModelFiles.Result) async throws -> BoardComponents.Found {
        switch result {
        case .notFound: return .notFound
        case .unreadable(let name, let reason): return .unreadable(name: name, reason: reason)
        case .file(let path, let format, let stamp):
            if format.isMesh { return try await loadMesh(path: path, format: format, stamp: stamp) }
            let key = ComponentModelCache.ReadKey(stamp: stamp, format: format)
            let tag = NodeTag(node: ComponentModelCache.sentinel, item: 0)
            let name = ModelFiles.fileName(of: path)
            let kernel = kernel
            do {
                let made = try await cache.solid(for: key) {
                    try await ModelFiles.read(at: path, format: format, stamp: stamp, kernel: kernel, tag: tag)
                }
                return .solid(made.solid, key, name: name, isCurrent: made.isCurrent)
            } catch let problem as ModelProblem {
                return .unreadable(name: name, reason: problem.reason)
            }
        }
    }

    /// What a path that gave no solid says: nothing was found, or the file could not be read.
    private mutating func noteProblem(of path: String) {
        switch found[path] ?? .notFound {
        case .notFound: problems.notFound.append(path)
        case .unreadable(let name, let reason): problems.unreadable.append("\(name) (\(reason))")
        case .solid, .mesh: break
        }
    }

    /// What one placed model came to.
    enum Placed {
        case solid(BoardComponents.Piece)
        case mesh(MeshPiece)
    }

    /// The piece for one model: scaled, tagged with this node and given its world plane; nil (the problem noted) when it can't be.
    mutating func place(_ model: ModelReference, of index: Int) async throws -> Placed? {
        let name: String
        switch found[model.path] ?? .notFound {
        case .solid(_, _, let solidName, _): name = solidName
        case .mesh(_, let meshName): name = meshName
        default:
            noteProblem(of: model.path)
            return nil
        }
        let scale = model.scale
        guard [scale.x, scale.y, scale.z].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            problems.unreadable.append("\(name) (its scale isn't positive)")
            return nil
        }
        let frame = ModelPlacement.frame(of: model, on: setting.board.footprints[index], boardOrigin: setting.origin,
                                         thickness: setting.thickness)
        guard let plane = BoardComponents.worldPlane(frame, in: setting.frame) else {
            problems.unreadable.append("\(name) (its position isn't valid)")
            return nil
        }
        switch found[model.path] ?? .notFound {
        case .mesh(let mesh, _):
            return try placeMesh(mesh, scale: scale, of: index, plane: plane, name: name).map(Placed.mesh)
        case .solid(let solid, let key, _, let isCurrent):
            return try await placeSolid(solid, key: key, isCurrent: isCurrent, scale: scale, at: (index, plane, name)).map(Placed.solid)
        default: return nil
        }
    }

    private mutating func placeSolid(_ solid: Solid, key: ComponentModelCache.ReadKey, isCurrent: Bool, scale: Vector3,
                                     at target: (footprint: Int, plane: Plane, name: String)) async throws -> BoardComponents.Piece? {
        let (index, plane, name) = (target.footprint, target.plane, target.name)
        let id = BoardComponents.ScaleID(key: key, scale: scale)
        if let kept = memo[id] { return BoardComponents.Piece(footprint: index, name: name, tool: kept, plane: plane) }
        var tool = solid
        if scale != Vector3(1, 1, 1) {
            let tag = NodeTag(node: ComponentModelCache.sentinel, item: 0)
            let kernel = kernel
            do {
                tool = try await cache.scaled(of: key, by: scale, isCurrent: isCurrent) {
                    try await ModelFiles.scale(solid, by: scale, kernel: kernel, tag: tag)
                }.solid
            } catch let problem as ModelProblem {
                problems.unreadable.append("\(name) (\(problem.reason))")
                return nil
            }
        }
        tool = ModelTags.retargeted(tool, to: node)
        memo[id] = tool
        return BoardComponents.Piece(footprint: index, name: name, tool: tool, plane: plane)
    }
}
