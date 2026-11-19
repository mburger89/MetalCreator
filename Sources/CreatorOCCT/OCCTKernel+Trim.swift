import COCCT
import CreatorGeometry
import CreatorKernel

/// Splitting a sheet by curves or bodies (NURBS spec NS-4, R2, R4, R6, R7).
extension OCCTKernel {
    static let danglingCutWarning = "Part of the cutter doesn't cross the surface from edge to edge, so it cut nothing there."

    /// A cutter as the shim takes it, and the way back from its elements to names.
    struct SplitInputs {
        var kind: Int32 = 2
        var wires: [OCCTShape] = []
        var counts: [Int] = []
        var direction = Vector3.unitZ
        var body: OCCTShape?
        var bodySolid: Solid?

        /// R2: curves are numbered over every curve's pieces in input order, a body's elements are its faces.
        func name(of element: Int) -> CutterName? {
            if let bodySolid {
                return bodySolid.topology.faces.indices.contains(element) ? .face(bodySolid.topology.faces[element].tags) : nil
            }
            var remaining = element
            for (index, count) in counts.enumerated() {
                if remaining < count { return .curve(index: index, piece: remaining) }
                remaining -= count
            }
            return nil
        }
    }

    func splitInputs(for cutter: TrimCutter) throws -> SplitInputs {
        var inputs = SplitInputs()
        switch cutter {
        case .curves(let curves, let projection, let along):
            inputs.kind = projection == .alongDirection ? 0 : 1
            if inputs.kind == 0 {
                guard along.isFinite, along.length > 1e-12 else { throw KernelError.invalidInput("The direction can't be zero.") }
                inputs.direction = along.normalized ?? along
            }
            inputs.wires = try curves.map { try curveShape(of: $0) }
            inputs.counts = curves.map(\.pieceCount)
        case .body(let solid):
            guard let shape = (solid.storage as? OCCTSolidStorage)?.shape else {
                throw KernelError.invalidInput("This surface was made by a different kernel.")
            }
            inputs.body = shape
            inputs.bodySolid = solid
        }
        return inputs
    }

    public func split(_ sheet: Solid, by cutter: TrimCutter, tag: NodeTag) async throws -> SheetSplit {
        try Task.checkCancellation()
        guard let source = (sheet.storage as? OCCTSolidStorage)?.shape else {
            throw KernelError.invalidInput("This surface was made by a different kernel.")
        }
        let inputs = try splitInputs(for: cutter)
        let flag = OCCTCancelFlag()
        let built: (shape: OCCTShape, tables: OCCTSplitTables)
        do {
            built = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> (shape: OCCTShape, tables: OCCTSplitTables) in
                    try OCCTShape.splitSheet(source, kind: inputs.kind, curves: inputs.wires, direction: inputs.direction,
                                             body: inputs.body, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("split", error) }
            throw KernelError.invalidInput(error.message)
        }
        try Task.checkCancellation()
        let tables = built.tables
        let names = Self.splitNames(tables, of: sheet, inputs: inputs, tag: tag)
        let whole = try solid(from: built.shape, history: names.history, inputs: [sheet.topology], tag: tag, operation: "split",
                              extraFaceTags: names.faceTags, edgeTagOverrides: names.edgeTags)
        let inside: Set<FaceID>? = tables.hasInside
            ? Set(tables.faces.indices.filter { tables.faces[$0].inside == 1 }.map { FaceID($0) }) : nil
        return SheetSplit(whole: whole, pieces: Self.orderedPieces(tables, in: whole), inside: inside,
                          warnings: tables.dangling ? [Self.danglingCutWarning] : [])
    }

    /// R2: each face keeps its source face's tags (the history) plus a `cutSide` per element it borders; an input edge keeps its
    /// tags and a cut edge is named by its element.
    static func splitNames(_ tables: OCCTSplitTables, of sheet: Solid, inputs: SplitInputs, tag: NodeTag)
        -> (history: [OCCTHistoryRecord], faceTags: [Int: Set<TopoTag>], edgeTags: [Int: Set<TopoTag>]) {
        let sides: [CutSide] = [.front, .back, .inside, .outside]
        var history: [OCCTHistoryRecord] = []
        var faceTags: [Int: Set<TopoTag>] = [:]
        for (index, face) in tables.faces.enumerated() {
            history.append(OCCTHistoryRecord(outFace: index, kind: .face, operand: 0, index: face.sourceFace - 1))
            for pair in face.pairs where sides.indices.contains(pair.side) {
                if let cutter = inputs.name(of: pair.element) {
                    faceTags[index, default: []].insert(TopoTag(tag, .cutSide(cutter, sides[pair.side])))
                }
            }
        }
        var edgeTags: [Int: Set<TopoTag>] = [:]
        for (index, edge) in tables.edges.enumerated() {
            if edge.sourceEdge > 0, sheet.topology.edges.indices.contains(edge.sourceEdge - 1) {
                edgeTags[index] = sheet.topology.edges[edge.sourceEdge - 1].tags
            } else if edge.sourceEdge == 0 {
                // A cut edge the shim couldn't match to an element still divides pieces, so it still gets a cut tag (the
                // placeholder `.curve(index: -1, piece: 0)` matches no cutter); a region pick reads the division from it.
                // Limit: every such edge shares the placeholder, so an Edges by Tag pick on one matches them all (rare: it
                // needs a failed ancestor lookup).
                edgeTags[index] = [TopoTag(tag, .boundary(.cut(inputs.name(of: edge.element) ?? .curve(index: -1, piece: 0))))]
            }
        }
        return (history, faceTags, edgeTags)
    }

    public func subSheet(_ faces: [FaceID], of sheet: Solid) throws -> Solid {
        guard let source = (sheet.storage as? OCCTSolidStorage)?.shape else {
            throw KernelError.invalidInput("This surface was made by a different kernel.")
        }
        guard !faces.isEmpty else { throw KernelError.invalidInput("A sheet needs at least one face.") }
        guard faces.allSatisfy({ sheet.topology.faces.indices.contains($0.rawValue) }) else {
            throw KernelError.invalidInput("That face isn't part of this sheet.")
        }
        let built: (shape: OCCTShape, tables: OCCTSplitTables)
        do {
            built = try Self.serialized { () throws -> (shape: OCCTShape, tables: OCCTSplitTables) in
                try OCCTShape.subSheet(of: source, faces: faces.map(\.rawValue))
            }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("sub sheet", error) }
            throw KernelError.invalidInput(error.message)
        }
        let history = built.tables.faces.enumerated().map {
            OCCTHistoryRecord(outFace: $0.offset, kind: .face, operand: 0, index: $0.element.sourceFace - 1)
        }
        var overrides: [Int: Set<TopoTag>] = [:]
        for (index, edge) in built.tables.edges.enumerated() where sheet.topology.edges.indices.contains(edge.sourceEdge - 1) {
            overrides[index] = sheet.topology.edges[edge.sourceEdge - 1].tags
        }
        let placeholder = NodeTag(node: NodeID(), item: 0)
        return try solid(from: built.shape, history: history, inputs: [sheet.topology], tag: placeholder, operation: "sub sheet",
                         edgeTagOverrides: overrides)
    }

    /// R6: the order is `SheetPieces.ordered`'s, shared with Trim Surface's region picks.
    static func orderedPieces(_ tables: OCCTSplitTables, in whole: Solid) -> [[FaceID]] {
        var groups: [Int: [Int]] = [:]
        for (index, face) in tables.faces.enumerated() { groups[face.piece, default: []].append(index) }
        return SheetPieces.ordered(groups: Array(groups.values), in: whole.topology)
    }
}
