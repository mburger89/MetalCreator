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

/// Sections, details and auxiliary views on OpenCascade's real parts (DR-3 R1 to R14, Review Focus 1 and 6): the hatch, the cut edge's
/// dimension through a width change and a cut that leaves the part, a detail's true millimetres, a hole seen face on.
@MainActor
struct DrawingSectionOCCTTests {
    /// A 40 by 20 by 10 box with its corner at the origin.
    func plate() -> DrawingBox {
        var box = DrawingBox(width: 40)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["height"] = .number(20)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["anchor"] = .integer(6)
        return box
    }

    func start(_ box: DrawingBox, orientation: StandardOrientation = .top) async throws -> (AppModel, ViewID) {
        let app = await AppModel.inDrawing(box.graph, kernel: OCCTKernel())
        let view = try #require(await app.placeBaseView())
        app.drawing.editor.setOrientation(orientation, of: view)
        await app.settle()
        return (app, view)
    }

    func cutter(_ points: [Vector2], viewing: Vector2) -> SectionCutter {
        SectionCutter(frame: StandardOrientation.top.frame, points: points, viewing: viewing)
    }

    func hatch(of view: ViewID, in app: AppModel) -> [SheetStroke] {
        app.drawing.editor.picture?.strokes.filter { $0.view == view && $0.layer == .hatch } ?? []
    }

    // MARK: Hatch

    @Test func theSectionIsHatchedAroundTheHole() async throws {
        var box = plate()
        let hole = box.builder.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(20, 10, -1)))])
        let holeSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(12)])
        let cut = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        box.builder.wire(hole, "profile", to: holeSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: cut, "target")
        box.builder.wire(holeSolid, "solid", to: cut, "tools")
        let link = Link(from: Endpoint(node: cut.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        let (app, base) = try await start(box)
        let section = try await app.insertSection(
            on: base, cutter: cutter([Vector2(-5, 10), Vector2(45, 10)], viewing: Vector2(0, 1)))
        let strokes = hatch(of: section, in: app)
        #expect(!strokes.isEmpty, "hatch strokes exist")
        let mapping = try #require(app.mapping(of: section))
        // The cut runs along +x from the line's start, so a section's horizontal coordinate is the part's x; the hole's gap is 17..23.
        var crossing = 0
        var left = 0, right = 0
        for stroke in strokes {
            for case .line(let a, let b) in stroke.segments {
                for step in 0...20 {
                    let point = mapping.model(a + (b - a) * (Double(step) / 20))
                    if point.x > 17 + 1e-6 && point.x < 23 - 1e-6 { crossing += 1 }
                    if point.x < 17 { left += 1 }
                    if point.x > 23 { right += 1 }
                }
            }
        }
        #expect(crossing == 0, "\(crossing) hatch samples lie across the hole's gap")
        #expect(left > 0 && right > 0, "hatch lies on both sides of the gap, so the gap is where the test says")
    }

    // MARK: Dimensions on a cut edge

    @Test func aCutEdgeDimensionFollowsAWidthChange() async throws {
        let box = plate()
        let (app, base) = try await start(box)
        let section = try await app.insertSection(
            on: base, cutter: cutter([Vector2(-5, 10), Vector2(45, 10)], viewing: Vector2(0, 1)))
        let bounds = try #require(app.drawing.editor.contents[section]?.projection?.bounds)
        let id = try #require(await app.dimensionEdge(of: section, at: Vector2(bounds.center.x, bounds.min.y)))
        #expect(app.texts(of: id).contains("40"), "\(app.texts(of: id))")
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(60)), name: "Width")
        await app.settle()
        #expect(app.texts(of: id).contains("60"), "\(app.texts(of: id))")
        #expect(app.report(of: id)?.status == .held)
    }

    @Test func aCutEdgeDimensionIsLostWhenItsCutLeavesThePart() async throws {
        let box = plate()
        let (app, base) = try await start(box)
        let line = cutter(
            [Vector2(-5, 5), Vector2(20, 5), Vector2(20, 15), Vector2(45, 15)], viewing: Vector2(0, 1))
        let section = try await app.insertSection(on: base, cutter: line)
        let bounds = try #require(app.drawing.editor.contents[section]?.projection?.bounds)
        // The right half of the drawing is cut 2's face (y = 15, x 20 to 40): its bottom edge is 20 long.
        let id = try #require(await app.dimensionEdge(of: section, at: Vector2(bounds.max.x - 10, bounds.min.y)))
        #expect(app.texts(of: id).contains("20"), "\(app.texts(of: id))")
        let before = app.report(of: id)
        #expect(before?.status == .held)
        // Drag the line by its mark 6 mm along +y: cut 2 runs at y = 21, beyond the part, and cut 0 (y = 11) still cuts it.
        await app.dragMark(on: base, from: Vector2(7.5, 5), by: Vector2(0, 6))
        #expect(app.undoTitle == "Undo Move Cutting Line")
        #expect(app.texts(of: id).contains("20?"), "\(app.texts(of: id))")
        #expect(app.report(of: id)?.status == .lost(.missing))
        // It is listed among the sheet's lost annotations and in an export's warnings, not only drawn with its question mark.
        let picture = try #require(app.drawing.editor.picture)
        #expect(picture.lostAnnotations.contains(id))
        let sheet = try #require(app.drawing.editor.sheet)
        let listed = AppModel.lostWarnings(on: sheet, in: picture, view: section)
        #expect(listed.count == 1 && listed[0].hasPrefix("On “\(sheet.name)”"), "\(listed)")
        app.undo()
        await app.settle()
        #expect(app.report(of: id)?.status == .held, "undo brings it back held")
        #expect(app.texts(of: id).contains("20"), "\(app.texts(of: id))")
    }

    // MARK: Details and auxiliary views

    @Test func aDetailOfTheTopViewMeasuresModelMillimetres() async throws {
        var box = plate()
        let hole = box.builder.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(20, 10, -1)))])
        let holeSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(12)])
        let cut = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        box.builder.wire(hole, "profile", to: holeSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: cut, "target")
        box.builder.wire(holeSolid, "solid", to: cut, "tools")
        let link = Link(from: Endpoint(node: cut.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        let (app, base) = try await start(box)
        // The Top view sees the hole face on; a 5:1 detail circles it.
        let editor = app.drawing.editor
        let mapping = try #require(app.mapping(of: base))
        editor.press(.detail)
        let center = mapping.sheet(Vector2(20, 10))
        let edge = center + Vector2(6 * mapping.scale, 0)
        editor.primaryChanged(to: editor.transform.screenPoint(center), modifiers: [])
        editor.primaryChanged(to: editor.transform.screenPoint(edge), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(edge), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(Vector2(260, 150)), modifiers: [])
        await app.settle()
        let detail = try #require(editor.document.sheets[0].views.first { $0.kind == .detail }?.id)
        try await app.editView(detail) { $0.scale = DrawingScale(numerator: 5, denominator: 1) }
        let id = try #require(await app.dimensionEdge(of: detail, at: Vector2(23, 10), offset: Vector2(14, 0)))
        #expect(app.texts(of: id).contains(where: { $0.contains("6") && $0.contains("Ø") }), "\(app.texts(of: id))")
    }

    @Test func aSectionOfTwoSolidsHatchesTwoAngles() async throws {
        var box = plate()
        let other = box.builder.add(RectangleNode.self, [
            "width": .number(40), "height": .number(20), "anchor": .integer(6), "plane": .plane(.through(Vector3(0, 30, 0))),
        ])
        let otherSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(10)])
        let merge = box.builder.add(MergeNode.self)
        box.builder.wire(other, "profile", to: otherSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: merge, "a")
        box.builder.wire(otherSolid, "solid", to: merge, "b")
        let link = Link(from: Endpoint(node: merge.id, socket: "list"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        let (app, base) = try await start(box)
        let section = try await app.insertSection(
            on: base, cutter: cutter([Vector2(20, -5), Vector2(20, 55)], viewing: Vector2(1, 0)))
        var angles: Set<Int> = []
        for stroke in hatch(of: section, in: app) {
            for case .line(let a, let b) in stroke.segments {
                var d = b - a
                guard d.length > 1e-9 else { continue }
                d = Vector2(d.x / d.length, d.y / d.length)
                if d.x < -1e-9 || (abs(d.x) <= 1e-9 && d.y < 0) { d = Vector2(-d.x, -d.y) }
                angles.insert(Int((atan2(d.y, d.x) * 1000).rounded()))
            }
        }
        #expect(angles.count == 2, "\(angles)")
    }

    // MARK: Auxiliary views

    /// A 30-40-50 wedge (a trapezoid on the Front plane, 20 deep) with a 10 mm hole drilled square to its inclined face.
    func wedge() -> DrawingBox {
        var box = DrawingBox(width: 60)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["height"] = .number(20)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["anchor"] = .integer(6)
        box.builder.graph.nodes[box.extrude.id]?.inputValues["distance"] = .number(40)
        let normal = Vector3(0.6, 0, 0.8)
        let slope = Plane(origin: Vector3(40, 10, 25), normal: normal, xAxis: Vector3(0, 1, 0))
        let block = box.builder.add(RectangleNode.self, ["width": .number(200), "height": .number(200), "plane": .plane(slope)])
        let blockSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(60)])
        let wedge = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        let circle = box.builder.add(CircleNode.self, ["diameter": .number(10), "plane": .plane(slope)])
        let drill = box.builder.add(ExtrudeNode.self, ["distance": .number(20), "reversed": .bool(true)])
        let drilled = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        box.builder.wire(block, "profile", to: blockSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: wedge, "target")
        box.builder.wire(blockSolid, "solid", to: wedge, "tools")
        box.builder.wire(circle, "profile", to: drill, "profile")
        box.builder.wire(wedge, "solid", to: drilled, "target")
        box.builder.wire(drill, "solid", to: drilled, "tools")
        let link = Link(from: Endpoint(node: drilled.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        return box
    }

    @Test func aHoleSquareToTheInclinedFaceReadsTrueInItsAuxiliaryView() async throws {
        let (app, front) = try await start(wedge(), orientation: .front)
        let editor = app.drawing.editor
        // The slope's edge runs from (20, 40) to (60, 10) in Front's plane; pick it at its middle, then place the view.
        let mapping = try #require(app.mapping(of: front))
        editor.press(.auxiliaryView)
        editor.primaryEnded(at: editor.transform.screenPoint(mapping.sheet(Vector2(40, 25))), modifiers: [])
        #expect(editor.auxiliaryDraft != nil, "\(editor.refusal ?? "no refusal")")
        // A first-angle view is dropped on the side it doesn't look from: here, behind the slope.
        let drop = mapping.sheet(Vector2(40, 25)) - Vector2(0.6, 0.8) * 100
        editor.primaryEnded(at: editor.transform.screenPoint(drop), modifiers: [])
        await app.settle()
        let aux = try #require(editor.document.sheets[0].views.first { $0.kind == .auxiliary }?.id)
        // Face on, the circle is a circle: a diameter dimension reads 10.
        let drawn = try #require(editor.contents[aux]?.projection)
        // (The far end's circle lies behind it, hidden; the mouth is the visible one.)
        let rim = drawn.lines.compactMap { line -> Vector2? in
            guard line.visibility == .visible, case .arc(let center, let radius, let start, let sweep) = line.curve,
                  abs(radius - 5) < 1e-6 else { return nil }
            let angle = start + sweep / 2
            return center + Vector2(cos(angle), sin(angle)) * radius
        }.first
        let onCircle = try #require(rim, "the hole's mouth is drawn as a circle in the auxiliary view")
        let diameter = try #require(await app.dimensionEdge(of: aux, at: onCircle, offset: Vector2(14, 0)))
        #expect(app.texts(of: diameter).contains(where: { $0.contains("10") && $0.contains("Ø") }), "\(app.texts(of: diameter))")
        // The slope's edge reads 50 in the auxiliary view, as it does in Front.
        let fifty = drawn.lines.compactMap { line -> Vector2? in
            guard line.visibility == .visible, case .line(let a, let b) = line.curve, abs((b - a).length - 50) < 1e-6 else { return nil }
            return a + (b - a) * 0.25
        }.first
        let slopeEdge = try #require(fifty, "the slope's edge is drawn at its true length")
        let long = try #require(await app.dimensionEdge(of: aux, at: slopeEdge, offset: Vector2(0, -10)))
        #expect(app.texts(of: long).contains("50"), "\(app.texts(of: long))")
        let inFront = try #require(await app.dimensionEdge(of: front, at: Vector2(30, 32.5), offset: Vector2(10, 10)))
        #expect(app.texts(of: inFront).contains("50"), "\(app.texts(of: inFront))")
        // Seen from the top the same circle is an ellipse, and a diameter there is refused.
        let top = try #require(await app.placeBaseView(at: Vector2(150, 230)))
        editor.setOrientation(.top, of: top)
        await app.settle()
        let topProjection = try #require(editor.contents[top]?.projection)
        let ellipse = topProjection.lines.compactMap { line -> Vector2? in
            if case .ellipse(let center, let axis, let major, let minor, let start, let sweep) = line.curve, line.visibility == .visible {
                let t = start + sweep / 2
                return center + axis * (major * cos(t)) + Vector2(-axis.y, axis.x) * (minor * sin(t))
            }
            return nil
        }.first
        let topRim = try #require(ellipse, "the hole is an ellipse in the Top view")
        let before = editor.document.sheets[0].annotations.count
        editor.press(.dimension)
        let topMapping = try #require(app.mapping(of: top))
        editor.primaryEnded(at: editor.transform.screenPoint(topMapping.sheet(topRim)), modifiers: [])
        #expect(editor.refusal == DrawingPick.circleSentence, "\(editor.refusal ?? "no refusal")")
        #expect(editor.document.sheets[0].annotations.count == before)
    }
}
#endif
