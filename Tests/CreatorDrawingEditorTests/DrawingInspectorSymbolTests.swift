import CreatorGeometry
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The symbol pages of the drawing inspector (DR-4 R15): what a datum, frame and surface page shows, and the sheet page's notes
/// and checks.
@MainActor
extension DrawingInspectorTests {
    private static let datumID = AnnotationID()
    private static let frameID = AnnotationID()
    private static let surfaceID = AnnotationID()

    private static var bottom: LeaderEnd {
        LeaderEnd(target: AnnotationEditorFixtures.pick(AnnotationEditorFixtures.topology(), 102), hint: Vector2(8, 0))
    }

    private func symbolScene(
        frame: FeatureControlFrame? = nil, surface: SurfaceTexture? = nil, units: DocumentUnits = .millimetres
    ) -> SelectionScene {
        let s = SelectionScene.make([], units: units)
        let plain = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05)], attachment: .feature(Self.bottom))
        let texture = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2), feature: Self.bottom,
            offset: Vector2(5, 5))
        let symbols = [
            DrawingAnnotation(
                id: Self.datumID, view: s.view.id,
                kind: .datumFeature(DatumFeature(letter: "A", attachment: .feature(Self.bottom), distance: -10))),
            DrawingAnnotation(id: Self.frameID, view: s.view.id, kind: .featureControl(frame ?? plain)),
            DrawingAnnotation(id: Self.surfaceID, view: s.view.id, kind: .surfaceTexture(surface ?? texture)),
        ]
        s.h.model.commitSheet("Setup") { sheet in for symbol in symbols { sheet.setAnnotation(symbol) } }
        s.h.log.commits.removeAll()
        return s
    }

    private func page(_ s: SelectionScene, _ id: AnnotationID) async throws -> (DrawingWindow, [String]) {
        s.h.model.selectedAnnotations = [id]
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(1400)), scaleFactor: 1) {
            DrawingInspector(model: s.h.model)
        }
        let shown = try window.window.elements(where: { _ in true }).compactMap { $0.value ?? $0.label }
        return (window, shown)
    }

    private func position(rows: Int = 1) -> FeatureControlFrame {
        let row = ToleranceRow(zone: .diameter, value: 0.1, datums: [DatumReference(letter: "A"), DatumReference(letter: "B")])
        return FeatureControlFrame(
            characteristic: .position, rows: Array(repeating: row, count: rows), attachment: .feature(Self.bottom))
    }

    @Test func aFramePageShowsOnlyWhatTheCharacteristicTakes() async throws {
        let flat = try await page(symbolScene(), Self.frameID).1
        #expect(flat.contains("Characteristic") && flat.contains("Tolerance"), "\(flat)")
        for row in ["Zone", "Material", "Projected", "Composite"] { #expect(!flat.contains(row), "\(row) in \(flat)") }
        #expect(flat.contains("Tangent plane"), "flatness takes Ⓣ: \(flat)")
        let located = try await page(symbolScene(frame: position()), Self.frameID).1
        for row in ["Zone", "Material", "Projected", "Datum 1", "Datum 2", "Datum 3", "Composite"] {
            #expect(located.contains(row), "\(row) in \(located)")
        }
        #expect(!located.contains("Tangent plane"), "position takes no tangent plane: \(located)")
    }

    @Test func aFramePageListsItsWarnings() async throws {
        let withDatum = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05, datums: [DatumReference(letter: "Z")])],
            attachment: .feature(Self.bottom))
        let shown = try await page(symbolScene(frame: withDatum), Self.frameID).1
        #expect(shown.contains("Flatness is a form tolerance and takes no datum."), "\(shown)")
    }

    @Test func asmeHidesConcentricityInTheMenu() {
        let iso = FrameInspector.characteristicOptions(current: .flatness, standard: .iso)
        #expect(iso.contains(.concentricity) && iso.contains(.symmetry))
        let asme = FrameInspector.characteristicOptions(current: .flatness, standard: .asme)
        #expect(!asme.contains(.concentricity) && !asme.contains(.symmetry))
        #expect(asme.count == GeometricCharacteristic.allCases.count - 2)
        let kept = FrameInspector.characteristicOptions(current: .concentricity, standard: .asme)
        #expect(kept.contains(.concentricity) && !kept.contains(.symmetry), "a frame that has it still shows it")
    }

    @Test func aDatumPageEditsItsLetter() async throws {
        let s = symbolScene()
        let (window, shown) = try await page(s, Self.datumID)
        #expect(shown.contains("Datum symbol") && shown.contains("Letter") && shown.contains("On a line"), "\(shown)")
        let field = try #require(try window.window.elements(role: .textField).first { $0.value == "A" })
        window.window.click(at: Point(x: field.frame.origin.x + 4, y: field.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        window.window.typeKey(.end)
        window.window.typeKey(.delete)
        window.window.typeText("B")
        window.window.typeKey(.return)
        try await window.window.runUntilIdle()
        #expect(s.h.log.commits.map(\.name) == ["Change Datum Letter"])
        guard case .datumFeature(let datum)? = s.h.model.sheet?.annotation(Self.datumID)?.kind else {
            Issue.record("no datum")
            return
        }
        #expect(datum.letter == "B")
    }

    @Test func aSurfacePageShowsMicroinchesInInches() async throws {
        let texture = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 1.6002), feature: Self.bottom,
            offset: Vector2(5, 5))
        let inches = DocumentUnits(length: .inches)
        let (window, shown) = try await page(symbolScene(surface: texture, units: inches), Self.surfaceID)
        #expect(shown.contains("Surface symbol") && shown.contains("Value (µin)"), "\(shown)")
        let fields = try window.window.elements(role: .textField).compactMap(\.value)
        #expect(fields.contains("63"), "\(fields)")
        let (mmWindow, mmShown) = try await page(symbolScene(surface: texture), Self.surfaceID)
        #expect(mmShown.contains("Value (µm)"), "\(mmShown)")
        #expect(try mmWindow.window.elements(role: .textField).compactMap(\.value).contains("1.6"))
    }

    @Test func theSheetPageHasNotesAndChecks() async throws {
        let withDatum = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05, datums: [DatumReference(letter: "Z")])],
            attachment: .feature(Self.bottom))
        let s = symbolScene(frame: withDatum)
        s.h.model.selectedAnnotations = []
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(1800)), scaleFactor: 1) {
            DrawingInspector(model: s.h.model)
        }
        let shown = try window.window.elements(where: { _ in true }).compactMap { $0.value ?? $0.label }
        for row in ["NOTES", "Edge break", "General surface", "CHECKS"] { #expect(shown.contains(row), "\(row) in \(shown)") }
        #expect(shown.contains { $0.hasSuffix("Flatness is a form tolerance and takes no datum.") }, "\(shown)")
        let clean = SelectionScene.make([])
        let cleanWindow = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(1800)), scaleFactor: 1) {
            DrawingInspector(model: clean.h.model)
        }
        let cleanShown = try cleanWindow.window.elements(role: .staticText).compactMap { $0.value ?? $0.label }
        #expect(cleanShown.contains("NOTES") && !cleanShown.contains("CHECKS"), "\(cleanShown)")
    }
}
