import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The inspector's setters for datum, frame and surface symbols (DR-4 R15): each one named step, each refusal in words, and no
/// step when the value is the one it already has.
@MainActor
@Suite("Symbol inspector model")
struct SymbolInspectorModelTests {
    private typealias Scene = SelectionScene
    private typealias Fixtures = AnnotationEditorFixtures

    private static let datumID = AnnotationID()
    private static let frameID = AnnotationID()
    private static let surfaceID = AnnotationID()
    private static let lettersSentence = "A datum letter is one or two capitals from A to Z, without I, O or Q."

    private static var bottom: LeaderEnd {
        LeaderEnd(target: Fixtures.pick(Fixtures.topology(), 102), hint: Vector2(8, 0))
    }

    private static var side: LeaderEnd {
        LeaderEnd(target: Fixtures.pick(Fixtures.topology(), 100), hint: Vector2(20, 5))
    }

    private func scene(
        frame: FeatureControlFrame? = nil, surface: SurfaceTexture? = nil, units: DocumentUnits = .millimetres
    ) -> Scene {
        let s = Scene.make([], units: units)
        var symbols = [
            DrawingAnnotation(
                id: Self.datumID, view: s.view.id,
                kind: .datumFeature(DatumFeature(letter: "A", attachment: .feature(Self.bottom), distance: -10))),
        ]
        let defaultFrame = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05)], attachment: .feature(Self.bottom))
        symbols.append(DrawingAnnotation(id: Self.frameID, view: s.view.id, kind: .featureControl(frame ?? defaultFrame)))
        let defaultSurface = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2), feature: Self.bottom,
            offset: Vector2(5, 5))
        symbols.append(
            DrawingAnnotation(id: Self.surfaceID, view: s.view.id, kind: .surfaceTexture(surface ?? defaultSurface)))
        s.h.model.commitSheet("Setup") { sheet in for symbol in symbols { sheet.setAnnotation(symbol) } }
        s.h.log.commits.removeAll()
        return s
    }

    private func frame(_ s: Scene) -> FeatureControlFrame {
        guard case .featureControl(let value)? = s.annotation(Self.frameID)?.kind else { fatalError("no frame") }
        return value
    }

    private func texture(_ s: Scene) -> SurfaceTexture {
        guard case .surfaceTexture(let value)? = s.annotation(Self.surfaceID)?.kind else { fatalError("no surface") }
        return value
    }

    private func letter(_ s: Scene) -> String {
        guard case .datumFeature(let value)? = s.annotation(Self.datumID)?.kind else { fatalError("no datum") }
        return value.letter
    }

    private func names(_ s: Scene) -> [String] { s.h.log.commits.map(\.name) }

    private func positionFrame() -> FeatureControlFrame {
        FeatureControlFrame(
            characteristic: .position,
            rows: [
                ToleranceRow(
                    zone: .diameter, value: 0.1, material: .maximum, freeState: true, tangentPlane: false,
                    projected: ProjectedZone(length: 5), datums: [DatumReference(letter: "A")]),
                ToleranceRow(zone: .diameter, value: 0.05, datums: [DatumReference(letter: "A")]),
            ], attachment: .feature(Self.bottom))
    }

    @Test func aLetterIsValidated() {
        let s = scene()
        s.h.model.setDatumLetter("b", of: Self.datumID)
        #expect(letter(s) == "B")
        #expect(names(s) == ["Change Datum Letter"])
        s.h.model.setDatumLetter("I", of: Self.datumID)
        #expect(s.h.model.refusal == Self.lettersSentence)
        #expect(letter(s) == "B")
        #expect(names(s).count == 1)
        s.h.model.setDatumLetter("", of: Self.datumID)
        #expect(s.h.model.refusal == Self.lettersSentence)
        s.h.model.setDatumLetter("AB", of: Self.datumID)
        #expect(letter(s) == "AB")
    }

    @Test func asmeRefusesConcentricity() {
        var saved = FeatureControlFrame(
            characteristic: .concentricity, rows: [ToleranceRow(value: 0.05)], attachment: .feature(Self.bottom))
        let s = scene(frame: saved)
        var document = s.h.model.document
        document.settings.standard = .asme
        s.h.model.replaceDocument(document)
        s.h.model.setCharacteristic(.symmetry, of: Self.frameID)
        #expect(s.h.model.refusal == "ASME Y14.5-2018 has no concentricity or symmetry symbol.")
        #expect(frame(s).characteristic == .concentricity)
        s.h.model.setToleranceValue(text: "0.2", row: 0, of: Self.frameID)
        saved.rows[0].value = 0.2
        #expect(frame(s) == saved, "a saved concentricity keeps its value when another field changes")
        s.h.model.setCharacteristic(.position, of: Self.frameID)
        #expect(frame(s).characteristic == .position)
    }

    @Test func changingTheCharacteristicDropsWhatItTakesNot() {
        let s = scene(frame: positionFrame())
        s.h.model.setCharacteristic(.circularity, of: Self.frameID)
        #expect(names(s) == ["Change Feature Control Frame"])
        let result = self.frame(s)
        #expect(result.characteristic == .circularity)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].zone == .width)
        #expect(result.rows[0].material == nil)
        #expect(result.rows[0].projected == nil)
        #expect(result.rows[0].tangentPlane == false)
        #expect(result.rows[0].value == 0.1)
        #expect(result.rows[0].datums == [DatumReference(letter: "A")], "datums stay")
    }

    @Test func diameterIsRefusedForFlatness() {
        let s = scene()
        s.h.model.setZone(.diameter, row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == "Flatness takes no diameter zone.")
        #expect(names(s).isEmpty)
        s.h.model.setMaterialCondition(.maximum, row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == "Flatness takes no material condition.")
        s.h.model.setProjectedZone(true, lengthText: "", row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == "Flatness takes no projected zone.")
        let circularity = FeatureControlFrame(
            characteristic: .circularity, rows: [ToleranceRow(value: 0.05)], attachment: .feature(Self.bottom))
        let other = scene(frame: circularity)
        other.h.model.setTangentPlane(true, row: 0, of: Self.frameID)
        #expect(other.h.model.refusal == "Circularity takes no tangent plane.")
        #expect(names(other).isEmpty)
        s.h.model.setTangentPlane(true, row: 0, of: Self.frameID)
        #expect(frame(s).rows[0].tangentPlane)
    }

    @Test func valuesParseInTheDocumentsUnit() {
        let inches = DocumentUnits(length: .inches)
        let s = scene(units: inches)
        s.h.model.setToleranceValue(text: "0.005", row: 0, of: Self.frameID)
        #expect(abs(frame(s).rows[0].value - 0.127) < 1e-9)
        s.h.model.setToleranceValue(text: "0.2 mm", row: 0, of: Self.frameID)
        #expect(abs(frame(s).rows[0].value - 0.2) < 1e-9)
        let mm = scene()
        mm.h.model.setToleranceValue(text: "0.2", row: 0, of: Self.frameID)
        #expect(frame(mm).rows[0].value == 0.2)
    }

    @Test func zeroAndNegativeAreRefused() {
        let s = scene(frame: positionFrame())
        for text in ["0", "-0.1", "abc", ""] {
            s.h.model.setToleranceValue(text: text, row: 0, of: Self.frameID)
            #expect(s.h.model.refusal == "A tolerance is a number greater than 0, such as 0.05.")
            s.h.model.refusal = nil
        }
        s.h.model.setProjectedZone(true, lengthText: "-3", row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == "A projected zone's length is a length greater than 0.")
        s.h.model.refusal = nil
        s.h.model.setProjectedZone(true, lengthText: "", row: 0, of: Self.frameID)
        #expect(frame(s).rows[0].projected == ProjectedZone(length: nil))
        s.h.model.setProjectedZone(true, lengthText: "8", row: 0, of: Self.frameID)
        #expect(frame(s).rows[0].projected == ProjectedZone(length: 8))
        s.h.model.setProjectedZone(false, lengthText: "8", row: 0, of: Self.frameID)
        #expect(frame(s).rows[0].projected == nil)
        #expect(frame(s).rows[0].value == 0.1)
    }

    @Test func datumsAreAListOfThree() {
        var base = positionFrame()
        base.rows = [ToleranceRow(zone: .diameter, value: 0.1)]
        let s = scene(frame: base)
        s.h.model.setDatum(0, letterText: "a", material: nil, row: 0, of: Self.frameID)
        s.h.model.setDatum(1, letterText: "B", material: .maximum, row: 0, of: Self.frameID)
        s.h.model.setDatum(2, letterText: "C", material: nil, row: 0, of: Self.frameID)
        #expect(
            frame(s).rows[0].datums == [
                DatumReference(letter: "A"), DatumReference(letter: "B", material: .maximum), DatumReference(letter: "C"),
            ])
        let before = names(s).count
        s.h.model.setDatum(3, letterText: "D", material: nil, row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == "A frame takes at most three datum references.")
        #expect(names(s).count == before)
        s.h.model.setDatum(1, letterText: "", material: nil, row: 0, of: Self.frameID)
        #expect(frame(s).rows[0].datums == [DatumReference(letter: "A")], "clearing 2 removes 2 and 3")
        s.h.model.setDatum(0, letterText: "O", material: nil, row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == Self.lettersSentence)
    }

    @Test func compositeOnlyForPositionAndProfile() {
        let s = scene()
        s.h.model.setComposite(true, of: Self.frameID)
        #expect(s.h.model.refusal == "Only position and profile frames can be composite.")
        #expect(names(s).isEmpty)
        let position = scene(
            frame: FeatureControlFrame(
                characteristic: .position, rows: [ToleranceRow(zone: .diameter, value: 0.1, datums: [DatumReference(letter: "A")])],
                attachment: .feature(Self.bottom)))
        position.h.model.setComposite(true, of: Self.frameID)
        #expect(frame(position).rows.count == 2)
        #expect(frame(position).rows[1] == frame(position).rows[0], "on copies row 0")
        position.h.model.setComposite(true, of: Self.frameID)
        #expect(names(position).count == 1)
        position.h.model.setComposite(false, of: Self.frameID)
        #expect(frame(position).rows.count == 1)
    }

    @Test func roughnessInMicroinches() {
        let s = scene(units: DocumentUnits(length: .inches))
        s.h.model.setRoughness(parameter: .ra, valueText: "63", of: Self.surfaceID)
        #expect(names(s) == ["Change Surface Symbol"])
        #expect(abs((texture(s).requirement.value ?? 0) - 1.6002) < 1e-9)
        let mm = scene()
        mm.h.model.setRoughness(parameter: .rz, valueText: "1,6", of: Self.surfaceID)
        #expect(texture(mm).requirement.parameter == .rz)
        #expect(texture(mm).requirement.value == 1.6)
        mm.h.model.setRoughness(parameter: .ra, valueText: "0", of: Self.surfaceID)
        #expect(mm.h.model.refusal == "A roughness value is a number greater than 0, such as 1.6.")
        mm.h.model.setRoughness(parameter: .ra, valueText: "", of: Self.surfaceID)
        #expect(texture(mm).requirement.value == 1.6, "a parameter with no value keeps the previous")
        mm.h.model.setRoughness(parameter: nil, valueText: "", of: Self.surfaceID)
        #expect(texture(mm).requirement.parameter == nil)
        #expect(texture(mm).requirement.value == nil)
        mm.h.model.setRoughness(parameter: .ra, valueText: "", of: Self.surfaceID)
        #expect(texture(mm).requirement.value == 3.2, "or 3.2")
    }

    @Test func standingNeedsAHorizontalLine() {
        let s = scene()
        s.h.model.setSurfaceStands(true, of: Self.surfaceID)
        #expect(texture(s).offset == nil)
        #expect(names(s) == ["Change Surface Symbol"])
        s.h.model.setSurfaceStands(false, of: Self.surfaceID)
        #expect(texture(s).offset != nil)
        let vertical = scene(
            surface: SurfaceTexture(
                requirement: SurfaceRequirement(process: .any), feature: Self.side, offset: Vector2(3, 3)))
        vertical.h.model.setSurfaceStands(true, of: Self.surfaceID)
        #expect(vertical.h.model.refusal == "A surface symbol stands only on a horizontal line, with the symbol above it.")
        #expect(texture(vertical).offset == Vector2(3, 3))
        #expect(names(vertical).isEmpty)
    }

    @Test func settersUpdateTheTemplates() {
        let s = scene()
        s.h.model.setToleranceValue(text: "0.3", row: 0, of: Self.frameID)
        #expect(s.h.model.frameTemplate?.rows.first?.value == 0.3)
        s.h.model.setLay(.crossed, of: Self.surfaceID)
        #expect(s.h.model.surfaceTemplate?.lay == .crossed)
        s.h.model.setSurfaceProcess(.removalProhibited, of: Self.surfaceID)
        #expect(s.h.model.surfaceTemplate?.requirement.process == .removalProhibited)
        s.h.model.setCharacteristic(.straightness, of: Self.frameID)
        #expect(s.h.model.frameTemplate?.characteristic == .straightness)
    }

    @Test func noChangeNoCommit() {
        let s = scene(frame: positionFrame())
        let m = s.h.model
        m.setDatumLetter("A", of: Self.datumID)
        m.setCharacteristic(.position, of: Self.frameID)
        m.setZone(.diameter, row: 0, of: Self.frameID)
        m.setToleranceValue(text: "0.1", row: 0, of: Self.frameID)
        m.setMaterialCondition(.maximum, row: 0, of: Self.frameID)
        m.setFreeState(true, row: 0, of: Self.frameID)
        m.setTangentPlane(false, row: 0, of: Self.frameID)
        m.setProjectedZone(true, lengthText: "5", row: 0, of: Self.frameID)
        m.setDatum(0, letterText: "A", material: nil, row: 0, of: Self.frameID)
        m.setComposite(true, of: Self.frameID)
        m.setSurfaceProcess(.removalRequired, of: Self.surfaceID)
        m.setRoughness(parameter: .ra, valueText: "3.2", of: Self.surfaceID)
        m.setLay(nil, of: Self.surfaceID)
        m.setSurfaceStands(false, of: Self.surfaceID)
        #expect(names(s).isEmpty, "\(names(s))")
        #expect(m.refusal == nil)
    }
}
