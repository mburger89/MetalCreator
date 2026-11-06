import MetalUI
import Testing
@testable import CreatorEditor

struct SegmentedCase: Sendable { let label: String; let options: [String] }

/// A labelled choice among options stays inside the inspector's 280-point content width, with every option reachable and the
/// label on a line of its own when the segments leave it no room (before MetalUI #206 its segmented `Picker` never narrowed:
/// its title wrapped a letter at a time and its segments ran off the panel).
@MainActor
struct SegmentedRowTests {
    nonisolated static let cases: [SegmentedCase] = [
        SegmentedCase(label: "Start continuity", options: ["Free", "Tangent (G1)", "Curvature (G2)"]),
        SegmentedCase(label: "Units", options: ["From file", "mm", "cm", "m", "in"]),
        SegmentedCase(label: "Continuity", options: ["Tangent (G1)", "Curvature (G2)"]),
        SegmentedCase(label: "Mode", options: ["Add", "Cut"]),
    ]

    /// The horizontal and vertical spread of everything a row drew, in points.
    private func extent(_ label: String, _ options: [String],
                        width: Double = SegmentedRow.inspectorWidth) -> (width: Double, height: Double, glyphs: Int) {
        let scene = renderHeadless {
            SegmentedRow(label: label, options: options, selected: 0, width: width) { _ in }
                .frame(width: width.px, alignment: .topLeading)
        }
        let xs = scene.glyphs.map { Double($0.bounds.origin.x) / 2 }
        let rights = scene.glyphs.map { Double($0.bounds.origin.x + $0.bounds.size.width) / 2 }
        let ys = scene.glyphs.map { Double($0.bounds.origin.y) / 2 }
        let bottoms = scene.glyphs.map { Double($0.bounds.origin.y + $0.bounds.size.height) / 2 }
        return ((rights.max() ?? 0) - (xs.min() ?? 0), (bottoms.max() ?? 0) - (ys.min() ?? 0), scene.glyphs.count)
    }

    @Test(arguments: cases)
    func theRowFitsThePanel(_ row: SegmentedCase) {
        let drawn = extent(row.label, row.options)
        #expect(drawn.width <= SegmentedRow.inspectorWidth, "\(row.label) is \(drawn.width) wide")
        // A label wrapped one letter a line would be as tall as it has letters.
        #expect(drawn.height < 90, "\(row.label) is \(drawn.height) tall")
        #expect(drawn.glyphs >= row.label.filter { !$0.isWhitespace }.count)
    }

    @Test func wideChoicesChooseAFormThatFits() {
        let wide = ["Free", "Tangent (G1)", "Curvature (G2)"]
        #expect(SegmentedRow.form(labelWidth: 40, widestOption: 20, count: 2, width: 280) == .inline)
        #expect(SegmentedRow.form(labelWidth: 110, widestOption: 80, count: 3, width: 280) != .inline)
        #expect(SegmentedRow.form(labelWidth: 110, widestOption: 80, count: 3, width: 460) == .inline)
        #expect(SegmentedRow.form(labelWidth: 60, widestOption: 75, count: 5, width: 280) == .menuBeside)
        #expect(SegmentedRow.form(labelWidth: 230, widestOption: 75, count: 5, width: 280) == .menuBelow)
        #expect(wide.count == 3)
    }

    /// MetalUI #206: its segmented picker now takes the offered width down to a floor, so the bare picker no longer
    /// overflows the panel (it did before; the rows still choose a form that keeps the label readable).
    @Test func theBarePickerNoLongerOverflows() {
        let scene = renderHeadless {
            Picker("Start continuity", selection: .constant(0)) {
                Text("Free").tag(0)
                Text("Tangent (G1)").tag(1)
                Text("Curvature (G2)").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: SegmentedRow.inspectorWidth.px, alignment: .topLeading)
        }
        let rights = scene.glyphs.map { Double($0.bounds.origin.x + $0.bounds.size.width) / 2 }
        let lefts = scene.glyphs.map { Double($0.bounds.origin.x) / 2 }
        #expect((rights.max() ?? 0) - (lefts.min() ?? 0) <= SegmentedRow.inspectorWidth)
    }

    @Test func aRowTheSegmentsFillKeepsItsOptionsSideBySide() {
        let roomy = extent("Mode", ["Add", "Cut"])
        #expect(roomy.glyphs == "ModeAddCut".count)
    }
}
