import Foundation
import Testing

@testable import CreatorDrawing

@Suite("General tolerance model")
struct GeneralToleranceModelTests {
    @Test func legacyISOStringsParse() {
        #expect(GeneralTolerance(legacy: "ISO 2768-mK", standard: .iso) == .iso2768(.m, .K))
        #expect(GeneralTolerance(legacy: "ISO 2768-f", standard: .iso) == .iso2768(.f, nil))
    }

    @Test func legacyASMEDefaultsParse() {
        let mm = GeneralTolerance(legacy: "±0.5, ±0.1, ±0.05 mm", standard: .asme)
        #expect(mm == GeneralTolerance.standardDefault(for: .asme, inches: false))
        guard case .asme(let metric) = mm else { Issue.record("not ASME"); return }
        #expect(metric.unit == .millimetres)
        #expect(metric.rows.map(\.places) == [0, 1, 2])
        #expect(metric.rows.map(\.text) == ["0.5", "0.1", "0.05"])
        let inches = GeneralTolerance(legacy: "±.03, ±.010, ±.005 in", standard: .asme)
        guard case .asme(let imperial) = inches else { Issue.record("not ASME"); return }
        #expect(imperial.unit == .inches)
        #expect(imperial.rows.map(\.places) == [1, 2, 3])
        #expect(imperial.rows.map(\.text) == [".03", ".010", ".005"])
    }

    @Test func anythingElseIsKeptAsText() {
        #expect(GeneralTolerance(legacy: "Per drawing 12", standard: .iso) == .text("Per drawing 12"))
        #expect(GeneralTolerance(legacy: "ISO 2768-xK", standard: .iso) == .text("ISO 2768-xK"))
        #expect(GeneralTolerance(legacy: "", standard: .iso) == .text(""))
    }

    @Test func textsMatchTheTitleBlock() {
        #expect(GeneralTolerance.standardDefault(for: .iso, inches: false).text == "ISO 2768-mK")
        #expect(GeneralTolerance.iso2768(.m, nil).text == "ISO 2768-m")
        #expect(GeneralTolerance.standardDefault(for: .asme, inches: false).text == "±0.5, ±0.1, ±0.05 mm")
        #expect(GeneralTolerance.standardDefault(for: .asme, inches: true).text == "±.03, ±.010, ±.005 in")
        #expect(GeneralTolerance.text("legacy").text == "legacy")
    }

    @Test func theToleranceFieldIsAutomatic() {
        #expect(!TitleBlockKey.tolerance.isTyped)
        let sheet = DrawingSheet(name: "Sheet 1")
        let picture = TitleBlockLayout.picture(
            sheet: sheet, settings: DrawingSettings(), facts: TitleBlockFacts(), sheetIndex: 0, sheetCount: 1)
        #expect(picture.texts.contains { $0.original == "ISO 2768-mK" })
    }

    @Test func decimalSignDefaultsToPoint() throws {
        #expect(DrawingSettings().decimalSign == .point)
        let data = try JSONEncoder().encode(DrawingSettings())
        #expect(String(bytes: data, encoding: .utf8)?.contains("decimalSign") == false)
        var comma = DrawingSettings()
        comma.decimalSign = .comma
        let back = try JSONDecoder().decode(DrawingSettings.self, from: try JSONEncoder().encode(comma))
        #expect(back.decimalSign == .comma)
    }

    @Test func onlyABlankTextIsEmpty() {
        #expect(GeneralTolerance.text("").isEmpty)
        #expect(GeneralTolerance.text("  ").isEmpty)
        #expect(!GeneralTolerance.text("x").isEmpty)
        #expect(!GeneralTolerance.iso2768(.m, .K).isEmpty)
        #expect(!GeneralTolerance.standardDefault(for: .asme, inches: true).isEmpty)
    }

    @Test func aStringToleranceInASettingsFileDecodes() throws {
        let text = #"{"standard":"iso","generalTolerance":"ISO 2768-mK","titleBlockDefaults":{}}"#
        let settings = try JSONDecoder().decode(DrawingSettings.self, from: Data(text.utf8))
        #expect(settings.generalTolerance == .iso2768(.m, .K))
        let back = try JSONDecoder().decode(DrawingSettings.self, from: try JSONEncoder().encode(settings))
        #expect(back == settings)
    }
}
