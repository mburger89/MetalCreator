import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation

/// A board from a KiCad file (KiCad import spec, KI-1): the board as a solid with its holes drilled, its outline as a profile and
/// its mounting holes as placements. The file is the node's `NodeSetting.pcbFile`, linked only. The parse is kept by
/// `KiCadBoardCache`, so moving or turning the board never reads the file again; a file saved in KiCad changes its stamp and is read
/// at the next evaluation. Each hole's walls carry the pad's key as their item, so a pick on one follows that pad.
public enum ImportKiCadBoardNode: NodeDefinition {
    public static let typeID = "creator.importKiCadBoard"
    public static let displayName = "Import KiCad Board"
    public static let category = NodeCategory.solid
    public static let factsTitle = "Board"
    public static let inputs = [
        SocketSpec("placement", .plane, defaultValue: .plane(.xy)),
        SocketSpec("origin", .integer, defaultValue: .integer(BoardOrigin.boardCentre.rawValue)),
        SocketSpec("vias", .bool, defaultValue: .bool(false)),
        SocketSpec("components", .bool, defaultValue: .bool(true)),
    ]
    public static let outputs = [
        SocketSpec("board", .solid),
        SocketSpec("outline", .profile),
        SocketSpec("mounting holes", .plane),
        SocketSpec("mounting hole diameters", .number, unit: .millimetres),
        SocketSpec("components", .solid),
        SocketSpec("component meshes", .mesh),
    ]
    public static let inspector = [
        InspectorSection(title: "File", controls: [.pcbFile(NodeSetting.pcbFile)]),
        InspectorSection(title: "Placement", controls: [.planePicker("placement"), .segmented("origin", options: BoardOrigin.options)]),
        InspectorSection(title: "Include", controls: [.toggle("vias", label: "Vias"), .toggle("components", label: "Components")]),
    ]

    static let defaultThickness = 1.6

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard let reference = context.node.inputValues[NodeSetting.pcbFile]?.fileReference else { throw BoardImportProblem.notChosen }
        guard let originChoice = BoardOrigin(rawValue: try inputs.integer("origin")) else {
            throw NodeError.invalidValue("“origin” must be \(BoardOrigin.options.formatted(.list(type: .or).locale(.messages))).")
        }
        let placement = try inputs.plane("placement")
        guard placement.origin.isFinite, let normal = placement.normal.normalized,
              let across = (placement.xAxis - normal * placement.xAxis.dot(normal)).normalized
        else { throw NodeError.invalidValue("“placement” has no direction.") }
        let frame = Plane(origin: placement.origin, normal: normal, xAxis: across)
        let includesVias = try inputs.bool("vias")

        let parsed = try await load(reference, context.images)
        let board = parsed.board
        var warnings: [String] = []
        let thickness = thickness(of: board, warnings: &warnings)
        if board.version > KiCadBoard.newestKnownVersion {
            warnings.append("This board is from a newer KiCad than MetalCreator knows. Check the result.")
        }
        guard let box = BoardFrame.bounds(of: parsed.outline.outer) else {
            throw NodeError.invalidValue("The board has no outline on Edge.Cuts.")
        }
        let origin = origin(originChoice, board: board, box: box, warnings: &warnings)

        let outer = parsed.outline.outer.map { BoardFrame.moved($0, by: origin) }
        let cutouts = parsed.outline.holes.map { $0.map { BoardFrame.moved($0, by: origin) } }
        let base = try await kernel.extrude(Profile2D(plane: .xy, outer: outer), distance: thickness,
                                            mode: .oneSided, tag: context.tag)
        let drilled = BoardHoles.placed(board, origin: origin, vias: includesVias)
        let cutters = zip(cutouts, parsed.outline.holeKeys).compactMap { loop, keys in
            keys.min().map { Cutter(loop: loop, item: $0) }
        }
        var solid = try await drill(base, holes: drilled, cutters: cutters, thickness: thickness, kernel: kernel, context: context)
        if let move = frame.placement, move != .identity {
            solid = try await kernel.transform(solid, by: move, tag: context.tag)
        }

        let top = frame.offset(by: thickness)
        let mounting = BoardHoles.mounting(board, origin: origin)
        var outputs = NodeOutputs([
            "board": .solid(solid),
            "outline": .profile(Profile2D(plane: top, outer: outer, holes: cutouts)),
        ], warnings: warnings)
        outputs.lists = [
            "mounting holes": mounting.map { .plane(Plane(origin: top.point($0.center), normal: top.normal, xAxis: top.xAxis)) },
            "mounting hole diameters": mounting.map { .number($0.diameter) },
            "components": [],
            "component meshes": [],
        ]
        outputs.facts = BoardFacts.facts(
            file: reference.fileName ?? "Board", board: board,
            size: BoardFacts.Vector2Size(width: box.max.x - box.min.x, height: box.max.y - box.min.y),
            thickness: thickness, drilled: drilled.count, mounting: mounting.count)
        return outputs
    }

    private static func load(_ reference: ImageReference, _ resolver: ImageResolver) async throws -> ParsedBoard {
        do {
            return try await KiCadBoardCache.shared.board(for: resolver.stamp(of: reference)) {
                try parse(resolver.pcbFileBytes(of: reference))
            }
        } catch let problem as KiCadProblem {
            throw NodeError.invalidValue(problem.message)
        }
    }

    private static func thickness(of board: KiCadBoard, warnings: inout [String]) -> Double {
        if let given = board.thickness, given.isFinite, given > 0 { return given }
        warnings.append("This board has no thickness, so \(defaultThickness.display) mm is used.")
        return defaultThickness
    }

    /// The point of the file that becomes the board frame's origin.
    private static func origin(_ choice: BoardOrigin, board: KiCadBoard, box: (min: Vector2, max: Vector2),
                               warnings: inout [String]) -> Vector2 {
        let centre = Vector2((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        switch choice {
        case .page: return Vector2(0, 0)
        case .boardCentre: return centre
        case .drillPlace:
            if let aux = board.auxAxisOrigin { return aux }
            warnings.append("This board has no drill/place origin, so the board centre is used.")
            return centre
        }
    }

    /// A cutout of the outline, cut as a tool named by its own lowest piece key, so redrawing another cutout never renames its walls.
    private struct Cutter {
        var loop: [Segment2D]
        var item: Int
    }

    /// Cuts every cutout and hole: one tool per distinct drill and one per cutout, all placed in one kernel call with each pad's or
    /// cutout's key as its item, subtracted in one.
    private static func drill(_ board: Solid, holes: [BoardHoles.Placed], cutters: [Cutter], thickness: Double,
                              kernel: any Kernel, context: EvalContext) async throws -> Solid {
        guard !holes.isEmpty || !cutters.isEmpty else { return board }
        let plan = ToolPlan(sizes: holes.map(\.size))
        var tools: [Solid] = []
        for size in plan.distinct {
            tools.append(try await kernel.extrude(BoardHoles.profile(for: size), distance: thickness + 2, mode: .oneSided,
                                                  tag: context.tag))
        }
        var placed = plan.toolIndex.map { tools[$0] }
        for cutter in cutters {
            let profile = Profile2D(plane: Plane.xy.offset(by: -1), outer: cutter.loop)
            placed.append(try await kernel.extrude(profile, distance: thickness + 2, mode: .oneSided, tag: context.tag))
        }
        let planes = holes.map(\.plane) + cutters.map { _ in Plane.xy }
        let copies = try await PlacementMoves.place(placed, planes: planes, items: holes.map(\.item) + cutters.map(\.item),
                                                    placedBy: context.node.id, kernel: kernel, tag: context.tag)
        return try await kernel.boolean(.subtract, board, copies, tag: context.tag)
    }

    /// The board a file of these bytes holds. Synchronous, so no loop's locals live across an `await`.
    static func parse(_ data: Data) throws -> ParsedBoard {
        var board = try KiCadBoardReader.read(data, isCancelled: { Task.isCancelled })
        try KeyAssigner.assign(&board)
        let outline = try OutlineChainer.chain(board.edgeItems, tolerance: board.chainingTolerance)
        return ParsedBoard(board: board, outline: outline)
    }
}
