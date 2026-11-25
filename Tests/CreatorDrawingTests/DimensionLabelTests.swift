import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct DimensionLabelTests {
    let iso = DimensionNumberTests.format()
    let inchesISO = DimensionNumberTests.format(.inches, .iso, precision: 3)
    let inchesASME = DimensionNumberTests.format(.inches, .asme, precision: 3)

    func size(
        _ mm: Double, _ tolerance: DimensionTolerance, symbol: SizeSymbol = .none, prefix: String = "", suffix: String = "",
        format: NumberFormat? = nil
    ) throws -> DimensionLabel {
        try DimensionLabel.size(
            mm, symbol: symbol, tolerance: tolerance, precision: nil, prefix: prefix, suffix: suffix, format: format ?? iso)
    }

    @Test func general() throws {
        #expect(try size(25, .general).plainText == "25")
    }

    @Test func symmetric() throws {
        #expect(try size(25, .symmetric(0.1)).plainText == "25 ±0.1")
        #expect(try size(25.4, .symmetric(0.127), format: inchesASME).plainText == "1.000 ±.005")
    }

    @Test func deviationStacksPadded() throws {
        let label = try size(25, .deviation(upper: 0.1, lower: -0.25))
        #expect(label.stack == StackedText(upper: "+0.10", lower: "-0.25"))
        #expect(label.lines == [[.text("25")]])
        let zero = try size(25, .deviation(upper: 0.1, lower: 0))
        #expect(zero.stack == StackedText(upper: "+0.1", lower: "0"))
        let inches = try size(25.4, .deviation(upper: 0.0254, lower: 0), format: inchesASME)
        #expect(inches.stack == StackedText(upper: "+.001", lower: "-.000"))
    }

    @Test func limitsStack() throws {
        let label = try size(25, .limits(upper: 0.1, lower: -0.1))
        #expect(label.stack == StackedText(upper: "25.1", lower: "24.9"))
        let diameter = try size(25, .limits(upper: 0.1, lower: 0), symbol: .diameter)
        #expect(diameter.stack == StackedText(upper: "25.1", lower: "25.0"))
        #expect(diameter.lines == [[.text("Ø")]])
    }

    @Test func reference() throws {
        #expect(try size(25, .reference).plainText == "(25)")
    }

    @Test func basicIsBoxed() throws {
        let label = try size(25, .basic)
        #expect(label.isBoxed)
        #expect(label.plainText == "25")
    }

    @Test func fitWithDeviations() throws {
        let label = try size(20, .fit(.hole(.H, grade: 7), showsDeviations: true), symbol: .diameter)
        #expect(label.lines == [[.text("Ø20 H7")]])
        #expect(label.trailing == "(+0.021/0)")
        let bare = try size(20, .fit(.hole(.H, grade: 7), showsDeviations: false), symbol: .diameter)
        #expect(bare.trailing.isEmpty)
    }

    @Test func fitInInches() throws {
        let label = try size(20, .fit(.hole(.H, grade: 7), showsDeviations: true), symbol: .diameter, format: inchesASME)
        #expect(label.trailing == "(+.0008/0)")
    }

    @Test func fitOnARadiusIsRefused() {
        #expect(throws: DrawingRefusal(sentence: "Fits apply to sizes: a diameter or a distance between two faces.")) {
            try size(20, .fit(.hole(.H, grade: 7), showsDeviations: true), symbol: .radius)
        }
        #expect(throws: DrawingRefusal.self) {
            try DimensionLabel.angle(
                1, tolerance: .fit(.hole(.H, grade: 7), showsDeviations: true), precision: nil, prefix: "", suffix: "", format: iso)
        }
    }

    @Test func fitOutOfRangeIsRefused() {
        #expect(throws: DrawingRefusal(sentence: "ISO 286 fits are given here for sizes over 0 up to 500 mm.")) {
            try size(600, .fit(.hole(.H, grade: 7), showsDeviations: true))
        }
    }

    @Test func prefixAndSuffix() throws {
        let label = try size(6, .general, symbol: .diameter, prefix: "2×", suffix: "TYP")
        #expect(label.plainText == "2× Ø6 TYP")
        #expect(label.hasTypedText)
        #expect(!(try size(6, .general)).hasTypedText)
        let stacked = try size(25, .deviation(upper: 0.1, lower: -0.1), suffix: "TYP")
        #expect(stacked.plainText == "25 +0.1/-0.1 TYP")
    }

    @Test func angles() throws {
        let label = try DimensionLabel.angle(
            .pi / 6, tolerance: .symmetric(0.5 * .pi / 180), precision: nil, prefix: "", suffix: "", format: iso)
        #expect(label.plainText == "30° ±0.5°")
        let stacked = try DimensionLabel.angle(
            .pi / 6, tolerance: .deviation(upper: 0.5 * .pi / 180, lower: 0), precision: nil, prefix: "", suffix: "", format: iso)
        #expect(stacked.stack == StackedText(upper: "+0.5°", lower: "0°"))
    }

    @Test func chamferForms() {
        #expect(DimensionLabel.chamfer(leg: 2, angle: .pi / 4, precision: nil, format: iso).plainText == "C2")
        #expect(DimensionLabel.chamfer(leg: 2, angle: .pi / 6, precision: nil, format: iso).plainText == "2 × 30°")
        let asme = DimensionNumberTests.format(.millimetres, .asme)
        #expect(DimensionLabel.chamfer(leg: 2, angle: .pi / 4, precision: nil, format: asme).plainText == "2 X 45°")
    }

    @Test func holeForms() {
        func hole(_ shape: HoleShape, _ format: NumberFormat? = nil) -> DimensionLabel {
            DimensionLabel.hole(shape, precision: nil, prefix: "", suffix: "", format: format ?? iso)
        }
        #expect(hole(HoleShape(diameter: 6)).plainText == "Ø6 THRU")
        let blind = hole(HoleShape(diameter: 6, depth: 10))
        #expect(blind.lines == [[.text("Ø6 "), .symbol(.depth), .text("10")]])
        #expect(blind.plainText == "Ø6 ↧10")
        let bore = hole(HoleShape(diameter: 6, counterbore: .init(diameter: 11, depth: 6)))
        #expect(bore.lines.count == 2)
        #expect(bore.plainText == "Ø6 THRU\n⌴Ø11 ↧6")
        let sink = hole(HoleShape(diameter: 6, countersink: .init(diameter: 12, angle: .pi / 2)))
        #expect(sink.plainText == "Ø6 THRU\n⌵Ø12 × 90°")
        let asmeSink = hole(
            HoleShape(diameter: 6, countersink: .init(diameter: 12, angle: .pi / 2)), DimensionNumberTests.format(.millimetres, .asme))
        #expect(asmeSink.lines[1].last == .text("Ø12 X 90°"))
    }

    @Test func ordinateOrigin() {
        #expect(DimensionLabel.ordinate(0, precision: nil, format: inchesISO).plainText == "0")
        #expect(DimensionLabel.ordinate(12.5, precision: nil, format: iso).plainText == "12.5")
    }

    @Test func lostAppendsAQuestionMark() throws {
        let label = try size(25, .deviation(upper: 0.1, lower: -0.1)).lost()
        #expect(label.lines == [[.text("25?")]])
        #expect(label.stack != nil)
        let blind = DimensionLabel.hole(HoleShape(diameter: 6, depth: 10), precision: nil, prefix: "", suffix: "", format: iso).lost()
        #expect(blind.lines[0].last == .text("10?"))
    }
}
