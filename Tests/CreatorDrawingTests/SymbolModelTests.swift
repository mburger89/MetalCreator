import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// DR-4 Task 1: the symbol kinds in the model, their coding, R2's kind rules and R14's repairs.
@Suite("Symbol model")
struct SymbolModelTests {
    let node = NodeID()

    func pick() -> EdgePick {
        EdgePick(
            key: EdgeKey([TopoTag(node: node, item: 0, role: .startCap)], [TopoTag(node: node, item: 0, role: .endCap)]),
            matchCount: 1)
    }

    func end() -> LeaderEnd { LeaderEnd(target: .edge(pick()), hint: Vector2(3, 4)) }

    func sheet(with annotations: [DrawingAnnotation], view: DrawingView) -> DrawingSheet {
        var sheet = DrawingSheet(name: "S", views: [view])
        for annotation in annotations { sheet.setAnnotation(annotation) }
        return sheet
    }

    func view() -> DrawingView {
        DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
    }

    func dimension(_ kind: DrawingDimensionKind, view: ViewID?) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view,
            kind: .dimension(
                DrawingDimension(kind: kind, anchors: [.edge(pick())], placement: DimensionPlacement(offset: 5, angle: 0))))
    }

    func datum(on attachment: SymbolAttachment, view: ViewID?, letter: String = "A") -> DrawingAnnotation {
        DrawingAnnotation(view: view, kind: .datumFeature(DatumFeature(letter: letter, attachment: attachment, distance: 8)))
    }

    func frame(
        on attachment: SymbolAttachment, view: ViewID?, characteristic: GeometricCharacteristic = .position,
        rows: [ToleranceRow] = [ToleranceRow(value: 0.1)]
    ) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view,
            kind: .featureControl(FeatureControlFrame(characteristic: characteristic, rows: rows, attachment: attachment)))
    }

    func surface(view: ViewID?) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view,
            kind: .surfaceTexture(SurfaceTexture(requirement: SurfaceRequirement(), feature: end())))
    }

    func roundTrip(_ sheet: DrawingSheet) throws -> DrawingSheet {
        try JSONDecoder().decode(DrawingSheet.self, from: JSONEncoder().encode(sheet))
    }

    func jsonText(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
    }

    @Test func everyKindRoundTripsByType() throws {
        let v = view()
        let row = ToleranceRow(
            zone: .diameter, value: 0.05, material: .maximum, freeState: true, tangentPlane: true,
            projected: ProjectedZone(length: 20),
            datums: [
                DatumReference(letter: "A"), DatumReference(letter: "B", material: .maximum),
                DatumReference(letter: "C", material: .least),
            ])
        let frame = frame(on: .feature(end()), view: v.id, rows: [row, ToleranceRow(value: 0.02, datums: [DatumReference(letter: "A")])])
        let datum = datum(on: .feature(end()), view: v.id, letter: "B")
        let standing = surface(view: v.id)
        var offset = surface(view: v.id)
        if case .surfaceTexture(var texture) = offset.kind {
            texture.offset = Vector2(2, 4)
            texture.lay = .perpendicular
            texture.requirement = SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 1.6)
            offset.kind = .surfaceTexture(texture)
        }
        for (annotation, name) in [
            (frame, "featureControl"), (datum, "datumFeature"), (standing, "surfaceTexture"), (offset, "surfaceTexture"),
        ] {
            let text = try jsonText(annotation.kind)
            #expect(text.contains("\"type\":\"\(name)\""))
            #expect(!text.contains("_0"))
            #expect(try JSONDecoder().decode(AnnotationKind.self, from: Data(text.utf8)) == annotation.kind)
        }
        let back = try roundTrip(sheet(with: [frame, datum, standing, offset], view: v))
        #expect(back.annotations.count == 4)
        #expect(back.annotation(frame.id) == frame)
        #expect(back.annotation(offset.id) == offset)
    }

    @Test func attachmentsRoundTrip() throws {
        let feature = SymbolAttachment.feature(end())
        let dimension = SymbolAttachment.dimension(AnnotationID())
        let featureText = try jsonText(feature)
        #expect(featureText.contains("\"type\":\"feature\""))
        #expect(try JSONDecoder().decode(SymbolAttachment.self, from: Data(featureText.utf8)) == feature)
        let dimensionText = try jsonText(dimension)
        #expect(dimensionText.contains("\"type\":\"dimension\""))
        #expect(!dimensionText.contains("_0"))
        #expect(try JSONDecoder().decode(SymbolAttachment.self, from: Data(dimensionText.utf8)) == dimension)
    }

    @Test func theAttachmentFigureRoundTrips() throws {
        let figure = AnnotationFigure.attachment(foot: Vector2(1, 2), along: Vector2(0, 1))
        let text = try jsonText(figure)
        #expect(text.contains("\"type\":\"attachment\""))
        #expect(text.contains("\"foot\"") && text.contains("\"along\""))
        #expect(try JSONDecoder().decode(AnnotationFigure.self, from: Data(text.utf8)) == figure)
    }

    struct Row {
        var characteristic: GeometricCharacteristic
        var title: String
        var family: ToleranceFamily
        var flags: [Bool]

        init(
            _ characteristic: GeometricCharacteristic, _ title: String, _ family: ToleranceFamily, _ diameter: Bool, _ material: Bool,
            _ tangent: Bool, _ projected: Bool, _ composite: Bool, _ asme: Bool
        ) {
            self.characteristic = characteristic
            self.title = title
            self.family = family
            flags = [diameter, material, tangent, projected, composite, asme]
        }
    }

    @Test func capabilitiesFollowTheTable() {
        // (characteristic, title, family, diameter, material, tangent, projected, composite, asme)
        let table: [Row] = [
            Row(.straightness, "Straightness", .form, true, true, false, false, false, true),
            Row(.flatness, "Flatness", .form, false, false, true, false, false, true),
            Row(.circularity, "Circularity", .form, false, false, false, false, false, true),
            Row(.cylindricity, "Cylindricity", .form, false, false, false, false, false, true),
            Row(.lineProfile, "Profile of a line", .profile, false, false, true, false, true, true),
            Row(.surfaceProfile, "Profile of a surface", .profile, false, false, true, false, true, true),
            Row(.parallelism, "Parallelism", .orientation, true, true, true, true, false, true),
            Row(.perpendicularity, "Perpendicularity", .orientation, true, true, true, true, false, true),
            Row(.angularity, "Angularity", .orientation, true, true, true, true, false, true),
            Row(.position, "Position", .location, true, true, false, true, true, true),
            Row(.concentricity, "Concentricity", .location, true, false, false, false, false, false),
            Row(.symmetry, "Symmetry", .location, false, false, false, false, false, false),
            Row(.circularRunout, "Circular run-out", .runout, false, false, false, false, false, true),
            Row(.totalRunout, "Total run-out", .runout, false, false, false, false, false, true),
        ]
        #expect(GeometricCharacteristic.allCases == table.map(\.characteristic))
        for row in table {
            let c = row.characteristic
            #expect(c.title == row.title)
            #expect(c.family == row.family)
            let actual = [
                c.takesDiameterZone, c.takesMaterialCondition, c.takesTangentPlane, c.takesProjectedZone, c.allowsComposite,
                c.isInASME,
            ]
            #expect(actual == row.flags, "\(c)")
        }
    }

    @Test func removingADimensionRemovesItsSymbols() {
        let v = view()
        let size = dimension(.linear(.horizontal), view: v.id)
        let onSize = frame(on: .dimension(size.id), view: v.id)
        let datumOnSize = datum(on: .dimension(size.id), view: v.id)
        let onLine = datum(on: .feature(end()), view: v.id, letter: "B")
        var sheet = sheet(with: [size, onSize, datumOnSize, onLine], view: v)
        #expect(sheet.symbols(on: size.id).map(\.id).sorted() == [onSize.id, datumOnSize.id].sorted())
        sheet.removeAnnotation(size.id)
        #expect(sheet.annotations == [onLine])
    }

    @Test func aSymbolOnAMissingDimensionIsDropped() throws {
        let v = view()
        let orphan = frame(on: .dimension(AnnotationID()), view: v.id)
        #expect(try roundTrip(sheet(with: [orphan], view: v)).annotations.isEmpty)
    }

    @Test func aSymbolOnANoteIsDropped() throws {
        let v = view()
        let note = DrawingAnnotation(view: v.id, kind: .note(DrawingNote(text: "N", position: Vector2(1, 1))))
        let onNote = frame(on: .dimension(note.id), view: v.id)
        #expect(try roundTrip(sheet(with: [note, onNote], view: v)).annotations == [note])
    }

    @Test func aSymbolOnAnotherViewsDimensionIsDropped() throws {
        let first = view()
        let second = DrawingView(kind: .base, source: node, orientation: .standard(.top), center: Vector2(10, 10))
        let size = dimension(.linear(.horizontal), view: first.id)
        let wrong = frame(on: .dimension(size.id), view: second.id)
        var sheet = DrawingSheet(name: "S", views: [first, second])
        sheet.setAnnotation(size)
        sheet.setAnnotation(wrong)
        #expect(try roundTrip(sheet).annotations == [size])
    }

    @Test func aSymbolOnAKindItCannotTakeIsDropped() throws {
        let v = view()
        let angle = dimension(.angle, view: v.id)
        let chain = dimension(.chain(.horizontal), view: v.id)
        let radius = dimension(.radius, view: v.id)
        let linear = dimension(.linear(.vertical), view: v.id)
        let diameter = dimension(.diameter, view: v.id)
        let dropped = [
            frame(on: .dimension(angle.id), view: v.id), frame(on: .dimension(chain.id), view: v.id),
            datum(on: .dimension(radius.id), view: v.id),
            DrawingAnnotation(
                view: v.id,
                kind: .datumFeature(DatumFeature(letter: "C", attachment: .dimension(angle.id)))),
        ]
        let kept = [frame(on: .dimension(radius.id), view: v.id), datum(on: .dimension(diameter.id), view: v.id, letter: "B")]
        let result = try roundTrip(sheet(with: [angle, chain, radius, linear, diameter] + dropped + kept, view: v))
        for annotation in dropped { #expect(result.annotation(annotation.id) == nil) }
        for annotation in kept { #expect(result.annotation(annotation.id) == annotation) }
    }

    @Test func acceptsFollowsR2() {
        let kinds: [(DrawingDimensionKind, datum: Bool, frame: Bool)] = [
            (.linear(.horizontal), true, true), (.linear(.vertical), true, true), (.linear(.aligned), true, true),
            (.baseline(.horizontal), false, false), (.chain(.horizontal), false, false), (.ordinate(.horizontal), false, false),
            (.radius, false, true), (.diameter, true, true), (.angle, false, false), (.chamfer, false, false),
        ]
        for (kind, datumOK, frameOK) in kinds {
            let target = dimension(kind, view: nil)
            #expect(SymbolAttachment.accepts(.datum, on: target) == datumOK, "datum on \(kind)")
            #expect(SymbolAttachment.accepts(.frame, on: target) == frameOK, "frame on \(kind)")
            #expect(!SymbolAttachment.accepts(.surface, on: target))
        }
        let callout = DrawingAnnotation(
            view: nil,
            kind: .holeCallout(HoleCallout(anchor: .edge(pick()), placement: DimensionPlacement(offset: 5, angle: 0))))
        #expect(SymbolAttachment.accepts(.datum, on: callout))
        #expect(SymbolAttachment.accepts(.frame, on: callout))
        #expect(!SymbolAttachment.accepts(.surface, on: callout))
        let note = DrawingAnnotation(view: nil, kind: .note(DrawingNote(text: "N", position: Vector2(0, 0))))
        #expect(!SymbolAttachment.accepts(.datum, on: note))
    }

    @Test func aSymbolWithoutAViewIsDropped() throws {
        let v = view()
        let free = datum(on: .feature(end()), view: nil)
        var sheet = DrawingSheet(name: "S", views: [v])
        sheet.setAnnotation(free)
        #expect(try roundTrip(sheet).annotations.isEmpty)
    }

    @Test func framesAreRepaired() throws {
        let v = view()
        let none = frame(on: .feature(end()), view: v.id, rows: [])
        let three = frame(on: .feature(end()), view: v.id, rows: [ToleranceRow(value: 1), ToleranceRow(value: 2), ToleranceRow(value: 3)])
        let flat = frame(
            on: .feature(end()), view: v.id, characteristic: .flatness, rows: [ToleranceRow(value: 1), ToleranceRow(value: 2)])
        let letters = (0..<4).map { DatumReference(letter: String(UnicodeScalar(65 + UInt8($0)))) }
        let four = frame(on: .feature(end()), view: v.id, rows: [ToleranceRow(value: 1, datums: letters)])
        let result = try roundTrip(sheet(with: [none, three, flat, four], view: v))
        #expect(result.annotation(none.id) == nil)
        func rows(_ annotation: DrawingAnnotation) -> [ToleranceRow] {
            if case .featureControl(let frame)? = result.annotation(annotation.id)?.kind { frame.rows } else { [] }
        }
        #expect(rows(three).map(\.value) == [1, 2])
        #expect(rows(flat).map(\.value) == [1])
        #expect(rows(four)[0].datums.map(\.letter) == ["A", "B", "C"])
    }

    @Test func sheetNotesAreWrittenOnlyWhenSet() throws {
        var sheet = DrawingSheet(name: "S")
        #expect(sheet.notes.isEmpty)
        #expect(!(try jsonText(sheet)).contains("\"notes\""))
        sheet.notes = SheetNotes(
            lines: ["Deburr.", "Paint black."], edgeBreak: EdgeBreak(minimum: 0.2, maximum: 0.5),
            surface: SurfaceRequirement(process: .removalRequired, parameter: .rz, value: 6.3))
        #expect(!sheet.notes.isEmpty)
        let text = try jsonText(sheet)
        #expect(text.contains("\"notes\""))
        let back = try roundTrip(sheet)
        #expect(back.notes == sheet.notes)
        #expect(back == sheet)
    }
}
