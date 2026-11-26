#if canImport(CreatorOCCT)
// Test fixture file: the bracket's drawing sheet for the drawing benchmarks.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// An A3 sheet of the §7.2 bracket for `DrawingBench`.
enum DrawingBenchFixtures {
    /// The drawings document with the bracket's Front, Right, Top and Isometric views on the app's current (empty) sheet, at the
    /// scale plan R8 picks for the first of them. Nothing is applied: the app's drawings are as they were. The app must be in
    /// Drawing mode with one empty sheet.
    @MainActor
    static func bracketSheet(_ app: AppModel) async throws -> DrawingDocument {
        let editor = app.drawing.editor
        let empty = editor.document
        // The editor's own first placement sets the sheet's scale (R8); read it, then put the empty sheet back.
        editor.press(.baseView)
        editor.primaryEnded(at: editor.transform.screenPoint(Vector2(120, 190)), modifiers: [])
        await app.settle()
        let placed = try #require(editor.document.sheets.first)
        let source = try #require(placed.views.first?.source)
        let scale = placed.scale
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()

        var document = empty
        let views: [(StandardOrientation, Vector2)] = [
            (.front, Vector2(120, 190)), (.right, Vector2(300, 190)), (.top, Vector2(120, 90)),
            (.isometricFrontRight, Vector2(300, 90)),
        ]
        document.sheets[0].scale = scale
        for (orientation, center) in views {
            document.sheets[0].setView(DrawingView(
                kind: .base, source: source, orientation: .standard(orientation), center: center))
        }
        return document
    }

    /// The model-plane height of the Top view's row of holes the section line runs through (the holes are at y = 8 mm either
    /// side of the plate's middle).
    static let sectionLineHeight = 8.0

    /// `bracketSheet` with a straight section of its Top view: a horizontal cutting line through a row of the plate's holes, looking
    /// toward +y of the Top view's plane, its view to the right of the sheet's middle. Nothing is applied when this returns.
    @MainActor
    static func sectionedBracketSheet(_ app: AppModel) async throws -> DrawingDocument {
        var document = try await bracketSheet(app)
        let top = try #require(document.sheets[0].views.first { $0.orientation == .standard(.top) })
        let cutter = SectionCutter(
            frame: top.orientation.frame, points: [Vector2(-40, sectionLineHeight), Vector2(40, sectionLineHeight)],
            viewing: Vector2(0, 1))
        document.sheets[0].setView(DrawingView(
            kind: .section, source: top.source, orientation: .custom(SectionFrame.frame(for: cutter)),
            center: Vector2(210, 60), derivation: .section(SectionLine(parent: top.id, cutter: cutter)), letter: "A"))
        return document
    }

    /// The number of dimensions `annotatedBracketSheet` puts on the sheet.
    static let dimensionCount = 30

    /// `bracketSheet` with `dimensionCount` held dimensions (lengths, diameters and angles) over its views. The dimensions are made
    /// from each view's real topology: every line edge a length, every full circle a diameter, and angles between lines that
    /// cross; the first `dimensionCount` that the composed sheet reports as held are kept, taken view by view in turn (an
    /// isometric view foreshortens every measure, plan R5, so it holds none). Nothing is applied when this returns.
    @MainActor
    static func annotatedBracketSheet(_ app: AppModel) async throws -> DrawingDocument {
        let empty = app.drawing.editor.document
        let plain = try await bracketSheet(app)
        try app.document.perform(.setDrawings(plain), name: "Test")
        app.refreshDrawing()
        await app.settle()
        var candidates = plain
        var perView: [[AnnotationID]] = []
        for view in plain.sheets[0].views {
            guard let topology = app.drawing.editor.contents[view.id]?.topology else { continue }
            var ids: [AnnotationID] = []
            for kind in candidateKinds(in: topology) {
                let annotation = DrawingAnnotation(view: view.id, kind: .dimension(kind))
                candidates.sheets[0].setAnnotation(annotation)
                ids.append(annotation.id)
            }
            perView.append(ids)
        }
        try app.document.perform(.setDrawings(candidates), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let reports = try #require(app.drawing.editor.picture?.annotationReports)
        var held = perView.map { $0.filter { reports[$0]?.status == .held } }
        var kept: Set<AnnotationID> = []
        while kept.count < dimensionCount, held.contains(where: { !$0.isEmpty }) {
            for index in held.indices where kept.count < dimensionCount && !held[index].isEmpty {
                kept.insert(held[index].removeFirst())
            }
        }
        var document = plain
        for annotation in candidates.sheets[0].annotations where kept.contains(annotation.id) {
            document.sheets[0].setAnnotation(annotation)
        }
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()
        return document
    }

    /// The distance between one part and the next along x, in millimetres (plan R20).
    static let partSpacing = 50.0

    /// R20's assembly: `parts` Outputs, each a 40 x 30 x 10 mm box less a 10 mm hole through it, `partSpacing` apart along x,
    /// built into a new document on OCCT. Returns the document and the Outputs' IDs in order.
    @MainActor
    static func assemblyDocument(parts: Int) throws -> (DocumentModel, [NodeID]) {
        let document = DocumentModel(registry: BuiltInNodes.registry, kernel: OCCTKernel())
        return (document, try addAssemblyParts(to: document, parts: parts))
    }

    /// Adds R20's parts to `document` (one edit per node, as the editor does) and returns their Outputs in order.
    @MainActor
    static func addAssemblyParts(to document: DocumentModel, parts: Int) throws -> [NodeID] {
        func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
            var node = BuiltInNodes.registry.makeNode(definition.typeID, at: Vector2(Double(document.graph.nodes.count) * 40, 0))
            node.inputValues.merge(values) { _, given in given }
            try document.perform(.addNode(node))
            return node
        }
        func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) throws {
            try document.perform(
                .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
        }
        var outputs: [NodeID] = []
        for index in 0..<parts {
            let plane = Plane(origin: Vector3(Double(index) * partSpacing, 0, 0), normal: .unitZ, xAxis: .unitX)
            let outline = try add(
                RectangleNode.self, ["width": .number(40), "height": .number(30), "plane": .plane(plane), "anchor": .integer(0)])
            let block = try add(ExtrudeNode.self, ["distance": .number(10)])
            try wire(outline, "profile", block, "profile")
            let holeProfile = try add(
                CircleNode.self, ["diameter": .number(10), "plane": .plane(plane.offset(by: 5))])
            let hole = try add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
            try wire(holeProfile, "profile", hole, "profile")
            let cut = try add(BooleanNode.self, ["operation": .integer(1)])
            try wire(block, "solid", cut, "target")
            try wire(hole, "solid", cut, "tools")
            let output = try add(OutputNode.self)
            try wire(cut, "solid", output, "solid")
            outputs.append(output.id)
        }
        return outputs
    }

    /// The assembly's sheet on the app's current (empty) sheet: the Front assembly view of `outputs`, with its Top and Right
    /// projected views aligned to it, at 1:5. Nothing is applied. The app must be in Drawing mode with one empty sheet.
    @MainActor
    static func assemblySheet(_ app: AppModel, outputs: [NodeID]) -> DrawingDocument {
        var document = app.drawing.editor.document
        document.sheets[0].scale = DrawingScale(numerator: 1, denominator: 5)
        let front = DrawingView(
            kind: .base, source: outputs[0], orientation: .standard(.front), center: Vector2(120, 190), assembly: outputs)
        document.sheets[0].setView(front)
        let drops: [(Vector2, Vector2)] = [(Vector2(120, 90), Vector2(0, -100)), (Vector2(300, 190), Vector2(180, 0))]
        for (center, offset) in drops {
            let rule = ProjectedViewRule.view(
                from: front.orientation.frame, dropOffset: offset, standard: document.settings.standard)
            document.sheets[0].setView(DrawingView(
                kind: .projected, source: outputs[0], orientation: .custom(rule.frame), scale: nil, center: center,
                alignment: ViewAlignment(parent: front.id, axis: rule.axis), assembly: outputs))
        }
        return document
    }

    /// `assemblySheet` with a balloon on each part's first lasting line edge in the Front view and the parts list. Nothing is
    /// applied when this returns.
    @MainActor
    static func balloonedAssemblySheet(_ app: AppModel, outputs: [NodeID]) async throws -> DrawingDocument {
        let empty = app.drawing.editor.document
        let plain = assemblySheet(app, outputs: outputs)
        try app.document.perform(.setDrawings(plain), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let front = try #require(plain.sheets[0].views.first { $0.kind == .base })
        let content = try #require(app.drawing.editor.contents[front.id])
        let topology = try #require(content.topology)
        var document = plain
        for span in content.parts {
            let scoped = topology.restricted(toFaces: span.faces)
            let picked = namedEdges(in: scoped).first { edge, _ in
                if case .line? = edge.curve { true } else { false }
            }
            let (edge, pick) = try #require(picked)
            let hint = edge.midpoint
            let balloon = Balloon(
                leader: LeaderEnd(target: .onPart(span.output, .edge(pick)), hint: Vector2(hint.x, hint.z)),
                offset: Vector2(0, 14))
            document.sheets[0].setAnnotation(DrawingAnnotation(view: front.id, kind: .balloon(balloon)))
        }
        document.sheets[0].setAnnotation(DrawingAnnotation(view: nil, kind: .partsList(PartsList())))
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()
        return document
    }

    /// The edges of a topology a dimension may be attached to: a lasting key and exactly one run.
    private static func namedEdges(in topology: Topology) -> [(EdgeInfo, EdgePick)] {
        var picks: [(EdgeInfo, EdgePick)] = []
        for edge in topology.edges.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard edge.curve != nil, let key = topology.key(of: edge),
                AnchorNaming.isLasting(key.first), AnchorNaming.isLasting(key.second) else { continue }
            let matches = topology.edges(matching: key)
            guard Topology.runCount(matches) == 1, matches.contains(where: { $0.id == edge.id }) else { continue }
            picks.append((edge, EdgePick(key: key, matchCount: matches.count, runCount: matches.count > 1 ? 1 : nil)))
        }
        return picks
    }

    /// Dimensions a view's topology offers, in edge order: a length per line, a diameter per full circle, then angles between pairs of
    /// non-parallel lines, interleaved.
    private static func candidateKinds(in topology: Topology) -> [DrawingDimension] {
        let placement = DimensionPlacement(offset: 8, angle: 0)
        let picks = namedEdges(in: topology)
        var lengths: [DrawingDimension] = []
        var diameters: [DrawingDimension] = []
        var lines: [(EdgeInfo, EdgePick)] = []
        for (edge, pick) in picks {
            switch edge.curve {
            case .line?:
                lengths.append(DrawingDimension(kind: .linear(.aligned), anchors: [.edge(pick)], placement: placement))
                lines.append((edge, pick))
            case .circle(_, _, _, _, let sweep)?:
                if sweep >= 2 * .pi - 1e-9 {
                    diameters.append(DrawingDimension(kind: .diameter, anchors: [.edge(pick)], placement: placement))
                }
            case nil: break
            }
        }
        var angles: [DrawingDimension] = []
        for first in lines.indices {
            for second in lines.indices where second > first && angles.count < 40 {
                guard let a = lines[first].0.direction, let b = lines[second].0.direction, a.cross(b).length > 0.1 else { continue }
                angles.append(
                    DrawingDimension(
                        kind: .angle, anchors: [.edge(lines[first].1), .edge(lines[second].1)], placement: placement))
            }
        }
        // Interleaved, so the first held ones of each kind are the ones kept.
        var kinds: [DrawingDimension] = []
        for index in 0..<max(lengths.count, diameters.count, angles.count) {
            for list in [lengths, diameters, angles] where index < list.count { kinds.append(list[index]) }
        }
        return kinds
    }
}
#endif
