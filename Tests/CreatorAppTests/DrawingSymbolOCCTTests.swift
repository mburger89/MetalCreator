#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Datum, frame and surface symbols on OpenCascade's real edges and tags (DR-4 R8, R11, R13): a width change keeps them held, a
/// chamfer that takes the datum's edge loses it, and a form tolerance with a datum warns in the PDF's export too.
@MainActor
struct DrawingSymbolOCCTTests {
    struct Part {
        var app: AppModel
        var view: ViewID
        var box: DrawingBox
        var datumA: AnnotationID
        var datumB: AnnotationID
        var toA: AnnotationID
        var toB: AnnotationID
        var diameter: AnnotationID
        var frame: AnnotationID
        var surface: AnnotationID
        var rule: Node
        var chamfer: Node
    }

    /// A 60 x 40 x 10 plate with a Ø10 hole through its centre, in a Top view at 1 : 1.
    func plate(width: Double = 60) async throws -> Part {
        var box = DrawingBox(width: width)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["height"] = .number(40)
        let hole = box.builder.add(CircleNode.self, ["diameter": .number(10), "plane": .plane(.through(Vector3(0, 0, -1)))])
        let holeSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(12)])
        let subtract = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        box.builder.wire(hole, "profile", to: holeSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: subtract, "target")
        box.builder.wire(holeSolid, "solid", to: subtract, "tools")
        // A chamfer waiting beside the Output: its rule picks nothing until a test gives it an edge and wires it in.
        let rule = box.builder.add(EdgesByTagNode.self)
        let chamfer = box.builder.add(ChamferNode.self, ["distance": .number(2)])
        box.builder.wire(subtract, "solid", to: rule, "solid")
        box.builder.wire(rule, "edges", to: chamfer, "edges")
        let link = Link(from: Endpoint(node: subtract.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        let app = await AppModel.inDrawing(box.builder.graph, kernel: OCCTKernel())
        let view = try #require(await app.placeBaseView(at: Vector2(150, 120)))
        let editor = app.drawing.editor
        editor.setOrientation(.top, of: view)
        await app.settle()
        let datumA = try #require(await app.placeSymbol(.datum, on: view, side: .bottom))
        let datumB = try #require(await app.placeSymbol(.datum, on: view, side: .left))
        app.drawing.editor.setDatumLetter("B", of: datumB)
        let toA = try #require(await dimension(app, view, from: Vector2(0, 0), to: Vector2(0, -20), at: Vector2(-12, -10)))
        let toB = try #require(await dimension(app, view, from: Vector2(0, 0), to: Vector2(-width / 2, 0), at: Vector2(-10, 8)))
        let diameter = try #require(await dimension(app, view, from: Vector2(5, 0), to: nil, at: Vector2(12, 12)))
        for id in [toA, toB] { editor.setTolerance(.basic, of: id) }
        await app.settle()
        let frame = try #require(await app.placeSymbol(.featureControlFrame, onDimension: diameter))
        editor.setCharacteristic(.position, of: frame)
        editor.setZone(.diameter, row: 0, of: frame)
        editor.setToleranceValue(text: "0.1", row: 0, of: frame)
        editor.setMaterialCondition(.maximum, row: 0, of: frame)
        editor.setDatum(0, letterText: "A", material: nil, row: 0, of: frame)
        editor.setDatum(1, letterText: "B", material: nil, row: 0, of: frame)
        let surface = try #require(await app.placeSymbol(.surfaceFinish, on: view, side: .bottom, distance: 14))
        await app.settle()
        return Part(
            app: app, view: view, box: box, datumA: datumA, datumB: datumB, toA: toA, toB: toB, diameter: diameter, frame: frame,
            surface: surface, rule: rule, chamfer: chamfer)
    }

    /// The dimension tool: a click at `first`, one at `second` when given, then one at `place` (model millimetres in the view).
    func dimension(_ app: AppModel, _ view: ViewID, from first: Vector2, to second: Vector2?, at place: Vector2) async -> AnnotationID? {
        let editor = app.drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }), let projection = editor.contents[view]?.projection,
            let center = ViewPlacement.centers(in: sheet)[view],
            let mapping = ViewMapping.of(projection: projection, center: center, scale: (sheet.view(view)?.scale ?? sheet.scale).value)
        else { return nil }
        let before = Set(sheet.annotations.map(\.id))
        editor.press(.dimension)
        for point in [first] + (second.map { [$0] } ?? []) + [place] {
            editor.primaryEnded(at: editor.transform.screenPoint(mapping.sheet(point)), modifiers: [])
        }
        await app.settle()
        return editor.document.sheet(sheet.id)?.annotations.map(\.id).first { !before.contains($0) }
    }

    func holdsEverything(_ part: Part) -> [String] {
        [part.datumA, part.datumB, part.toA, part.toB, part.diameter, part.frame, part.surface].compactMap { id in
            guard let report = part.app.report(of: id) else { return "\(id): no report" }
            return report.status == .held ? nil : "\(id): \(report.status)"
        }
    }

    @Test func symbolsAreHeldAndWarnNothing() async throws {
        let part = try await plate()
        #expect(holdsEverything(part).isEmpty, "\(holdsEverything(part))")
        #expect(part.app.report(of: part.frame)?.warnings == [])
        let url = temporaryURL("plate.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await part.app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.isEmpty, "\(warnings)")
    }

    @Test func symbolsStayHeldThroughAWidthChange() async throws {
        let part = try await plate()
        try part.app.document.perform(.setInput(part.box.rectangle.id, "width", .number(80)), name: "Width")
        await part.app.settle()
        #expect(holdsEverything(part).isEmpty, "\(holdsEverything(part))")
        let frame = try #require(part.app.report(of: part.frame))
        let diameter = try #require(part.app.report(of: part.diameter))
        let labelRect = try #require(diameter.labelRect)
        #expect(frame.frame.max.y <= labelRect.min.y + 1e-6, "the frame is still under the Ø label")
        let picture = try #require(part.app.drawing.editor.picture)
        let datum = try #require(picture.annotationReports[part.datumA])
        let viewFrame = try #require(picture.viewFrames[part.view])
        #expect(datum.frame.max.y >= viewFrame.min.y - 20 && datum.frame.min.y <= viewFrame.min.y + 1e-6, "A's foot is on the bottom edge")
    }

    @Test func aRemovedEdgeLosesItsDatum() async throws {
        let part = try await plate()
        // The edge between the top face (+z) and the front face (y = -20), found on the evaluated plate.
        guard case .ready(let solids, _, _) = DrawingSession.content(of: part.box.output.id, in: part.app.document).state,
            let solid = solids.first
        else {
            Issue.record("no solid")
            return
        }
        let edge = try #require(solid.topology.edges.first { info in
            guard case .line(let a, let b)? = info.curve else { return false }
            return abs(a.y + 20) < 1e-6 && abs(b.y + 20) < 1e-6 && abs(a.z - 10) < 1e-6 && abs(b.z - 10) < 1e-6
        })
        let link = Link(from: Endpoint(node: part.chamfer.id, socket: "solid"), to: Endpoint(node: part.box.output.id, socket: "solid"))
        try part.app.document.perform(
            .batch([.setInput(part.rule.id, NodeSetting.picks, .edgePicks(solid.topology.picks(for: [edge.id]))), .connect(link)]),
            name: "Chamfer")
        await part.app.settle()
        for lost in [part.datumA, part.toA] {
            let report = try #require(part.app.report(of: lost))
            #expect(report.isLost, "the edge is gone: \(report.status)")
            #expect(part.app.texts(of: lost).contains { $0.hasSuffix("?") || $0 == "A" }, "\(part.app.texts(of: lost))")
        }
        #expect(part.app.report(of: part.frame)?.status == .held)
        #expect(part.app.report(of: part.frame)?.warnings == [], "A is still defined by its symbol, lost or not")
        let url = temporaryURL("lost.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await part.app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.contains { $0.contains("lost what it was attached to") }, "\(warnings)")
    }

    @Test func aFlatnessWithADatumWarns() async throws {
        let part = try await plate()
        let flat = try #require(await part.app.placeSymbol(.featureControlFrame, on: part.view, side: .left, distance: 14))
        let editor = part.app.drawing.editor
        editor.setCharacteristic(.flatness, of: flat)
        editor.setDatum(0, letterText: "A", material: nil, row: 0, of: flat)
        await part.app.settle()
        let sentence = "Flatness is a form tolerance and takes no datum."
        #expect(part.app.report(of: flat)?.warnings == [sentence])
        let url = temporaryURL("flat.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await part.app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.contains { $0.hasSuffix(sentence) }, "\(warnings)")
    }
}
#endif
