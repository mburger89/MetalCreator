// Test fixture file: several Outputs (one box each) shown as one assembly view in the app, over a FakeKernel that can compound.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// `widths.count` boxes, each Rectangle → Extrude → Output, the Outputs named `names`.
@MainActor
struct AssemblyParts {
    var builder = GraphBuilder()
    var rectangles: [Node] = []
    var extrudes: [Node] = []
    var outputs: [Node] = []

    init(widths: [Double] = [20, 30, 40], names: [String] = ["Bolt", "Nut", "Plate"]) {
        for (index, width) in widths.enumerated() {
            let rectangle = builder.add(RectangleNode.self, ["width": .number(width)], at: Vector2(0, 200 * Double(index)))
            let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 200 * Double(index)))
            var output = builder.add(OutputNode.self, at: Vector2(480, 200 * Double(index)))
            output.name = names[index]
            builder.replace(output)
            builder.wire(rectangle, "profile", to: extrude, "profile")
            builder.wire(extrude, "solid", to: output, "solid")
            rectangles.append(rectangle)
            extrudes.append(extrude)
            outputs.append(output)
        }
    }

    var graph: Graph { builder.graph }
    var ids: [NodeID] { outputs.map(\.id) }
}

/// The faces and edges of the parts side by side, as the compound hook of a test kernel makes them.
func concatenatedSolids(_ solids: [Solid]) -> Solid {
    var faces: [FaceInfo] = [], edges: [EdgeInfo] = []
    var bounds = solids[0].bounds
    for solid in solids {
        let (faceOffset, edgeOffset) = (faces.count, edges.count)
        faces += solid.topology.faces.map { var face = $0; face.id = FaceID(face.id.rawValue + faceOffset); return face }
        edges += solid.topology.edges.map {
            var edge = $0
            edge.id = EdgeID(edge.id.rawValue + edgeOffset)
            edge.faces = edge.faces.map { FaceID($0.rawValue + faceOffset) }
            return edge
        }
        bounds = bounds.union(solid.bounds)
    }
    return Solid(topology: Topology(faces: faces, edges: edges), bounds: bounds, storage: solids[0].storage)
}

extension AppModel {
    /// The app showing `parts` in Drawing mode with one sheet, over a kernel that compounds.
    static func inAssembly(
        _ parts: AssemblyParts = AssemblyParts(), templates: DrawingTemplateStore = DrawingTemplateStore()
    ) async -> (app: AppModel, kernel: FakeKernel) {
        let kernel = FakeKernel()
        await kernel.setCompoundHook { concatenatedSolids($0) }
        await kernel.setSectionCutHook { part, _, _ in part }
        let app = AppModel(kernel: kernel, file: GraphFile(graph: parts.graph), templates: templates)
        await app.settle()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        return (app, kernel)
    }

    /// A click of the Assembly View tool; returns the new view.
    @discardableResult
    func placeAssemblyView(at point: Vector2 = Vector2(150, 150)) async -> ViewID? {
        let editor = drawing.editor
        let before = Set(editor.document.sheets.flatMap(\.views).map(\.id))
        editor.press(.assemblyView)
        editor.primaryEnded(at: editor.transform.screenPoint(point), modifiers: [])
        await settle()
        return editor.document.sheets.flatMap(\.views).map(\.id).first { !before.contains($0) }
    }

    /// The solid `output` holds now.
    func solid(of output: NodeID) -> Solid? {
        if case .ready(let solids, _, _) = DrawingSession.content(of: output, in: document).state { solids.first } else { nil }
    }

    /// A balloon on a line edge of `output`'s part in `view`, added to the drawings as one edit (the compound's edges overlap on a
    /// FakeKernel, so no click could tell the parts apart). `edge` picks which line edge of the part.
    @discardableResult
    func addBalloon(on output: NodeID, in view: ViewID, edge: Int = 0, offset: Vector2 = Vector2(12, 12)) throws -> AnnotationID {
        let solid = try #require(solid(of: output))
        let topology = solid.topology
        let lines = topology.edges.filter { $0.kind == .line }
        let info = lines[edge]
        let key = try #require(topology.key(of: info))
        let pick = EdgePick(key: key, matchCount: topology.edges(matching: key).count)
        let leader = LeaderEnd(target: .onPart(output, .edge(pick)), hint: Vector2(0, 0))
        var drawings = drawing.editor.document
        let index = try #require(drawings.sheets.firstIndex { $0.view(view) != nil })
        let annotation = DrawingAnnotation(view: view, kind: .balloon(Balloon(leader: leader, offset: offset)))
        drawings.sheets[index].setAnnotation(annotation)
        try document.perform(.setDrawings(drawings), name: "Test")
        refreshDrawing()
        return annotation.id
    }

    /// A horizontal dimension of an x-direction line edge of `output`'s part in `view`, added to the drawings as one edit.
    @discardableResult
    func addDimension(on output: NodeID, in view: ViewID) throws -> AnnotationID {
        let solid = try #require(solid(of: output))
        let topology = solid.topology
        let alongX = topology.edges.filter { (edge: EdgeInfo) -> Bool in
            let x: Double = edge.direction?.x ?? 0
            return edge.kind == .line && abs(abs(x) - 1.0) < 1e-9
        }
        let info = try #require(alongX.first)
        let key = try #require(topology.key(of: info))
        let pick = EdgePick(key: key, matchCount: topology.edges(matching: key).count)
        var drawings = drawing.editor.document
        let index = try #require(drawings.sheets.firstIndex { $0.view(view) != nil })
        let dimension = DrawingDimension(
            kind: .linear(.horizontal), anchors: [.onPart(output, .edge(pick))], placement: DimensionPlacement(offset: 10, angle: 0))
        let annotation = DrawingAnnotation(view: view, kind: .dimension(dimension))
        drawings.sheets[index].setAnnotation(annotation)
        try document.perform(.setDrawings(drawings), name: "Test")
        refreshDrawing()
        return annotation.id
    }

    /// A parts list on the open sheet, standing on the title block, added as one edit.
    @discardableResult
    func addPartsList() throws -> AnnotationID {
        var drawings = drawing.editor.document
        let index = try #require(drawings.sheets.firstIndex { $0.id == drawing.editor.currentSheet })
        let annotation = DrawingAnnotation(view: nil, kind: .partsList(PartsList()))
        drawings.sheets[index].setAnnotation(annotation)
        try document.perform(.setDrawings(drawings), name: "Test")
        refreshDrawing()
        return annotation.id
    }
}
