import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation

/// The components of an imported board (KiCad import spec, Components): one solid per footprint, made of its STEP, compressed STEP
/// or IGES models, each read once, scaled once per distinct scale and placed as KiCad places it.
enum BoardComponents {
    static let maxDistinctModels = 10_000
    static let maxModelBytes = 256 << 20
    static let listedNames = 8

    /// What a board's components came to.
    struct Outcome {
        var solids: [Solid] = []
        var warnings: [String] = []
        var dependencies: [FileDependency] = []
        /// How many footprints have a component.
        var withModel: Int { solids.count }
    }

    /// Where the node stands: the board in its own frame, and the world frame it is placed in.
    struct Setting {
        var board: KiCadBoard
        var origin: Vector2
        var thickness: Double
        var frame: Plane
        var folder: String
    }

    /// What one distinct model path came to.
    enum Found {
        case notFound
        case unreadable(name: String, reason: String)
        case solid(Solid, ComponentModelCache.ReadKey, name: String)
    }

    /// One model of a footprint, placed.
    struct Piece {
        var footprint: Int
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
        let settings = KiCadSettingsFiles.read()
        outcome.dependencies = settings.dependencies
        let variables = KiCadPathVariables.merged(environment: ProcessInfo.processInfo.environment,
                                                  settings: settings.variables, platform: .current)
        var placer = Placer(setting: setting, kernel: kernel, cache: cache, node: context.node.id)
        for path in paths {
            let resolved = ModelFiles.resolve(path, folder: setting.folder, variables: variables)
            outcome.dependencies += resolved.dependencies
            placer.found[path] = try await placer.load(resolved.result)
        }
        var pieces: [Piece] = []
        for index in order {
            guard !visible[index].isEmpty else {
                let name = setting.board.footprints[index].reference
                placer.problems.noModel.append(name.isEmpty ? "unnamed" : name)
                continue
            }
            for model in visible[index] {
                if let piece = try await placer.place(model, of: index) { pieces.append(piece) }
            }
        }
        for path in paths { placer.noteProblem(of: path) }
        outcome.solids = try await assemble(pieces, setting: setting, kernel: kernel, context: context, problems: &placer.problems)
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
                                 problems: inout Problems) async throws -> [Solid] {
        guard !pieces.isEmpty else { return [] }
        let items = pieces.map { KiCadKey.item(for: setting.board.footprints[$0.footprint].identity) }
        let placed = try await PlacementMoves.place(pieces.map(\.tool), planes: pieces.map(\.plane), items: items,
                                                    placedBy: context.node.id, kernel: kernel,
                                                    tag: NodeTag(node: context.node.id, item: 0))
        var solids: [Solid] = []
        var start = 0
        while start < pieces.count {
            var end = start + 1
            while end < pieces.count, pieces[end].footprint == pieces[start].footprint { end += 1 }
            if end - start == 1 {
                solids.append(placed[start])
            } else {
                let parts = (start..<end).map { retagged(placed[$0], model: $0 - start) }
                do {
                    solids.append(try await kernel.compound(parts, tag: NodeTag(node: context.node.id, item: items[start])))
                } catch let error as KernelError {
                    let name = setting.board.footprints[pieces[start].footprint].reference
                    problems.unreadable.append("\(name) (\(ModelFiles.reason(from: error.userMessage)))")
                }
            }
            start = end
        }
        return solids
    }

    /// The k-th model of a footprint names its faces `(k << 32) + i`, so two models never share a name (ruling R1).
    static func retagged(_ solid: Solid, model k: Int) -> Solid {
        guard k > 0 else { return solid }
        var topology = solid.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = Set(topology.faces[index].tags.map { tag in
                guard case .imported(let face) = tag.role else { return tag }
                return TopoTag(node: tag.node, item: tag.item, role: .imported(face: (k << 32) + face))
            })
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: solid.storage)
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
    private var memo: [BoardComponents.ScaleID: Solid] = [:]

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
            let key = ComponentModelCache.ReadKey(stamp: stamp, format: format.solidFormat, node: node)
            let tag = NodeTag(node: node, item: 0)
            let name = ModelFiles.fileName(of: path)
            let kernel = kernel
            do {
                let solid = try await cache.solid(for: key) {
                    try await ModelFiles.read(at: path, format: format, kernel: kernel, tag: tag)
                }
                return .solid(solid, key, name: name)
            } catch let problem as ModelProblem {
                return .unreadable(name: name, reason: problem.reason)
            }
        }
    }

    /// What a path that gave no solid says: nothing was found, or the file could not be read.
    mutating func noteProblem(of path: String) {
        switch found[path] ?? .notFound {
        case .notFound: problems.notFound.append(path)
        case .unreadable(let name, let reason): problems.unreadable.append("\(name) (\(reason))")
        case .solid: break
        }
    }

    /// The piece for one model: scaled and given its world plane; nil (the problem noted) when it can't be.
    mutating func place(_ model: ModelReference, of index: Int) async throws -> BoardComponents.Piece? {
        guard case .solid(let solid, let key, let name) = found[model.path] ?? .notFound else { return nil }
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
        guard scale != Vector3(1, 1, 1) else { return BoardComponents.Piece(footprint: index, tool: solid, plane: plane) }
        let id = BoardComponents.ScaleID(key: key, scale: scale)
        if let kept = memo[id] { return BoardComponents.Piece(footprint: index, tool: kept, plane: plane) }
        let tag = NodeTag(node: node, item: 0)
        let kernel = kernel
        do {
            let scaled = try await cache.scaled(of: key, by: scale) {
                try await ModelFiles.scale(solid, by: scale, kernel: kernel, tag: tag)
            }
            memo[id] = scaled
            return BoardComponents.Piece(footprint: index, tool: scaled, plane: plane)
        } catch let problem as ModelProblem {
            problems.unreadable.append("\(name) (\(problem.reason))")
            return nil
        }
    }
}
