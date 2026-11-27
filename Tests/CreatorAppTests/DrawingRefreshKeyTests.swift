import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The refresh key ignores where an annotation sits (drawings speed R5): a drag of a placement field starts no last-good refresh,
/// while anything `AnnotationRefresh.lastGood` reads (an anchor, a hint, the side a dimension's offset points to) still does.
@MainActor
struct DrawingRefreshKeyTests {
    enum Moved: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case dimensionOffset, balloonPosition, notePosition, symbolPosition
        var testDescription: String { rawValue }
    }

    func start() async throws -> (AppModel, DimensionPlate, ViewID) {
        let plate = DimensionPlate()
        let app = await AppModel.inDrawing(plate.graph)
        let view = try #require(await app.placeBaseView())
        return (app, plate, view)
    }

    /// The annotation with `change` applied, committed as one edit.
    func edit(_ app: AppModel, _ id: AnnotationID, _ change: (inout DrawingAnnotation) -> Void) async throws {
        var drawings = app.drawing.editor.document
        let index = try #require(drawings.sheets.firstIndex { $0.annotation(id) != nil })
        var annotation = try #require(drawings.sheets[index].annotation(id))
        change(&annotation)
        drawings.sheets[index].setAnnotation(annotation)
        try app.document.perform(.setDrawings(drawings), name: "Move")
        app.refreshDrawing()
        await app.settle()
    }

    func addNote(_ app: AppModel, in view: ViewID) async throws -> AnnotationID {
        var drawings = app.drawing.editor.document
        let index = try #require(drawings.sheets.firstIndex { $0.view(view) != nil })
        let note = DrawingAnnotation(view: view, kind: .note(DrawingNote(text: "Deburr", position: Vector2(10, 10))))
        drawings.sheets[index].setAnnotation(note)
        try app.document.perform(.setDrawings(drawings), name: "Add Note")
        app.refreshDrawing()
        await app.settle()
        return note.id
    }

    /// Moves the placement field of `moved`'s annotation ten times, one edit each, and counts the refreshes those started.
    func refreshesStartedByTenMoves(of moved: Moved) async throws -> Int {
        let (app, plate, view) = try await start()
        let id: AnnotationID
        switch moved {
        case .dimensionOffset: id = try #require(await app.dimensionBottomEdge(of: view))
        case .balloonPosition: id = try app.addBalloon(on: plate.box.output.id, in: view)
        case .notePosition: id = try await addNote(app, in: view)
        case .symbolPosition: id = try #require(await app.placeSymbol(.datum, on: view))
        }
        await app.settle()
        let before = app.drawingRefreshStarts
        for step in 1...10 {
            let delta = Double(step)
            try await edit(app, id) { annotation in
                switch annotation.kind {
                case .dimension(var value):
                    value.placement.offset = -8 - delta
                    value.placement.textShift = delta
                    annotation.kind = .dimension(value)
                case .balloon(var value):
                    value.offset = Vector2(12 + delta, 12 + delta)
                    annotation.kind = .balloon(value)
                case .note(var value):
                    value.position = Vector2(10 + delta, 10)
                    annotation.kind = .note(value)
                case .datumFeature(var value):
                    value.distance += delta
                    annotation.kind = .datumFeature(value)
                default: break
                }
            }
        }
        return app.drawingRefreshStarts - before
    }

    @Test(arguments: Moved.allCases)
    func aPlacementDragStartsNoRefresh(moved: Moved) async throws {
        #expect(try await refreshesStartedByTenMoves(of: moved) == 0)
    }

    @Test func aDimensionDraggedByTheEditorStartsNoRefresh() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let editor = app.drawing.editor
        editor.press(.select)
        let start = editor.transform.screenPoint(try #require(app.report(of: id)?.textCenter))
        editor.primaryChanged(to: start, modifiers: [])
        let before = app.drawingRefreshStarts
        for step in 1...10 { editor.primaryChanged(to: start + Vector2(0, Double(step) * 2), modifiers: []) }
        editor.primaryEnded(at: start + Vector2(0, 20), modifiers: [])
        await app.settle()
        #expect(app.drawingRefreshStarts == before)
    }

    @Test func anAnchorChangeStartsOne() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let topology = try #require(app.solid(of: plate.box.output.id)).topology
        let current = try #require(app.drawing.editor.document.sheets[0].annotation(id)).kind
        guard case .dimension(let held) = current else { Issue.record("not a dimension"); return }
        let picks: [AnchorTarget] = topology.edges.filter { (edge: EdgeInfo) -> Bool in
            edge.kind == .line && abs(abs(edge.direction?.x ?? 0) - 1.0) < 1e-9
        }.compactMap { info in
            topology.key(of: info).map { .edge(EdgePick(key: $0, matchCount: topology.edges(matching: $0).count)) }
        }
        let other = try #require(picks.first { $0 != held.anchors[0].unwrapped })
        let before = app.drawingRefreshStarts
        try await edit(app, id) { annotation in
            guard case .dimension(var value) = annotation.kind else { return }
            value.anchors[0] = other
            annotation.kind = .dimension(value)
        }
        #expect(app.drawingRefreshStarts == before + 1)
    }

    @Test func undoAfterADragRestoresTheFigure() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let remembered = try #require(app.drawing.editor.remembered[id])
        let editor = app.drawing.editor
        editor.press(.select)
        let start = editor.transform.screenPoint(try #require(app.report(of: id)?.textCenter))
        editor.primaryChanged(to: start, modifiers: [])
        for step in 1...6 { editor.primaryChanged(to: start + Vector2(0, Double(step) * 3), modifiers: []) }
        editor.primaryEnded(at: start + Vector2(0, 18), modifiers: [])
        await app.settle()
        app.undo()
        await app.settle()
        #expect(app.drawing.editor.remembered[id] == remembered, "the figure is the one before the drag")
        // The model still refreshes after the undo: the key still follows what the figure reads.
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        #expect(app.drawing.editor.remembered[id]?.values == [60])
    }

    // MARK: What the key keeps and what lastGood reads

    func figure(_ annotation: DrawingAnnotation, in topology: Topology) -> LastGood? {
        let format = NumberFormat(units: .millimetres, settings: DrawingSettings())
        return AnnotationRefresh.pass {
            AnnotationRefresh.lastGood(
                for: annotation, topology: topology, frame: StandardOrientation.top.frame, format: format, standard: .iso, parts: [],
                isPictorial: false)
        }
    }

    func line(in topology: Topology) throws -> AnchorTarget {
        let info = try #require(topology.edges.first { (edge: EdgeInfo) -> Bool in
            edge.kind == .line && abs(abs(edge.direction?.x ?? 0) - 1.0) < 1e-9
        })
        let key = try #require(topology.key(of: info))
        return .edge(EdgePick(key: key, matchCount: topology.edges(matching: key).count))
    }

    @Test func strippedFieldsDoNotChangeTheFigure() async throws {
        let (app, plate, _) = try await start()
        let topology = try #require(app.solid(of: plate.box.output.id)).topology
        let target = try line(in: topology)
        let end = LeaderEnd(target: target, hint: Vector2(20, 0))
        let view = ViewID()
        func dimension(offset: Double, shift: Double?) -> DrawingAnnotation {
            DrawingAnnotation(
                id: AnnotationID(), view: view,
                kind: .dimension(DrawingDimension(
                    kind: .linear(.horizontal), anchors: [target],
                    placement: DimensionPlacement(offset: offset, angle: 0, textShift: shift))))
        }
        func twins(_ name: String, _ make: (Double) -> AnnotationKind) -> (String, DrawingAnnotation, DrawingAnnotation) {
            (name, DrawingAnnotation(view: view, kind: make(1)), DrawingAnnotation(view: view, kind: make(7)))
        }
        let pairs: [(String, DrawingAnnotation, DrawingAnnotation)] = [
            ("dimension", dimension(offset: 5, shift: nil), dimension(offset: 9, shift: 3)),
            twins("datum") { .datumFeature(DatumFeature(letter: "A", attachment: .feature(end), distance: 8 * $0)) },
            twins("frame") { .featureControl(FeatureControlFrame(
                characteristic: .flatness, rows: [ToleranceRow(zone: .width, value: 0.1)], attachment: .feature(end),
                offset: Vector2($0, 2))) },
            twins("surface") { .surfaceTexture(SurfaceTexture(
                requirement: SurfaceRequirement(process: .any), feature: end, offset: Vector2($0, 2))) },
            twins("balloon") { .balloon(Balloon(leader: end, offset: Vector2($0, $0))) },
            twins("partsList") { .partsList(PartsList(bottomRight: Vector2($0, $0))) },
            twins("revisionTable") { .revisionTable(RevisionTable(rows: [], topRight: Vector2($0, $0))) },
        ]
        for (name, first, second) in pairs {
            #expect(first != second, "\(name): the pair differs as stored")
            #expect(first.placementStripped.kind == second.placementStripped.kind, "\(name): the key sees no difference")
            #expect(figure(first, in: topology) == figure(second, in: topology), "\(name): the figure is the same")
        }
        // The held kinds really produce a figure, so the comparison above is not nil against nil.
        for name in ["dimension", "datum", "frame", "surface"] {
            let pair = try #require(pairs.first { $0.0 == name })
            #expect(figure(pair.1, in: topology) != nil, "\(name) holds on this part")
        }
        // The hole callout has no hole on a box, so its figure is nil either way; only its stripped kind is compared.
        let callout = HoleCallout(anchor: target, placement: DimensionPlacement(offset: 4, angle: 0.5, textShift: 2))
        var moved = callout
        moved.placement = DimensionPlacement(offset: -9, angle: 1, textShift: nil)
        #expect(
            DrawingAnnotation(view: view, kind: .holeCallout(callout)).placementStripped.kind
                == DrawingAnnotation(view: view, kind: .holeCallout(moved)).placementStripped.kind)
        // Centre marks and lines hold no placement field: stripping leaves them as they are.
        let mark = DrawingAnnotation(view: view, kind: .centreMark(CentreMark(anchor: target)))
        #expect(mark.placementStripped == mark)
    }

    /// Radius, diameter and chamfer never read `placement.angle` (only an angle dimension's sector does), so a drag that writes it
    /// each step changes no key; an angle dimension's angle stays.
    @Test func onlyAnAngleDimensionKeepsItsPlacementAngle() async throws {
        let (app, plate, _) = try await start()
        let topology = try #require(app.solid(of: plate.box.output.id)).topology
        let target = try line(in: topology)
        let view = ViewID()
        func dimension(_ kind: DrawingDimensionKind, angle: Double) -> DrawingAnnotation {
            DrawingAnnotation(
                id: AnnotationID(), view: view,
                kind: .dimension(DrawingDimension(
                    kind: kind, anchors: [target], placement: DimensionPlacement(offset: 5, angle: angle))))
        }
        for (name, kind) in [("radius", DrawingDimensionKind.radius), ("diameter", .diameter), ("chamfer", .chamfer)] {
            #expect(
                dimension(kind, angle: 0).placementStripped.kind == dimension(kind, angle: 2).placementStripped.kind,
                "\(name): the angle is stripped")
        }
        #expect(dimension(.angle, angle: 0).placementStripped.kind != dimension(.angle, angle: 2).placementStripped.kind)
    }

    @Test func aRadiusDragThatWritesTheAngleStartsNoRefresh() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        try await edit(app, id) { annotation in
            guard case .dimension(var value) = annotation.kind else { return }
            value.kind = .radius
            annotation.kind = .dimension(value)
        }
        let before = app.drawingRefreshStarts
        for step in 1...10 {
            try await edit(app, id) { annotation in
                guard case .dimension(var value) = annotation.kind else { return }
                value.placement.angle = Double(step) * 0.3
                value.placement.offset = -8 - Double(step)
                annotation.kind = .dimension(value)
            }
        }
        #expect(app.drawingRefreshStarts == before)
    }

    @Test func whatLastGoodReadsStaysInTheKey() async throws {
        let (app, plate, _) = try await start()
        let topology = try #require(app.solid(of: plate.box.output.id)).topology
        let target = try line(in: topology)
        let view = ViewID()
        func dimension(offset: Double, angle: Double = 0) -> DrawingAnnotation {
            DrawingAnnotation(
                id: AnnotationID(), view: view,
                kind: .dimension(DrawingDimension(
                    kind: .linear(.horizontal), anchors: [target], placement: DimensionPlacement(offset: offset, angle: angle))))
        }
        // The side the offset points to picks which end of a line the dimension measures from.
        #expect(dimension(offset: 5).placementStripped.kind != dimension(offset: -5).placementStripped.kind)
        #expect(dimension(offset: 5).placementStripped.kind == dimension(offset: 50).placementStripped.kind)
        // Only an angle dimension's angle is read (its sector, in `onlyAnAngleDimensionKeepsItsPlacementAngle`); a linear one's is stripped.
        #expect(dimension(offset: 5, angle: 0).placementStripped.kind == dimension(offset: 5, angle: 2).placementStripped.kind)
        // A symbol's hint finds its foot.
        func datum(hint: Vector2) -> DrawingAnnotation {
            DrawingAnnotation(
                view: view, kind: .datumFeature(DatumFeature(letter: "A", attachment: .feature(LeaderEnd(target: target, hint: hint)))))
        }
        #expect(datum(hint: Vector2(1, 0)).placementStripped.kind != datum(hint: Vector2(2, 0)).placementStripped.kind)
        // A balloon's leader is kept whole: it names the part.
        func balloon(hint: Vector2) -> DrawingAnnotation {
            DrawingAnnotation(view: view, kind: .balloon(Balloon(leader: LeaderEnd(target: target, hint: hint), offset: .zero)))
        }
        #expect(balloon(hint: Vector2(1, 0)).placementStripped.kind != balloon(hint: Vector2(2, 0)).placementStripped.kind)
    }
}
