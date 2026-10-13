import CreatorGraph
import Testing
@testable import CreatorApp

/// The words and options on the legend (fields spec §6).
struct FieldLegendLabelsTests {
    func legend(_ range: FieldPreviewRange? = FieldPreviewRange(low: 0, mid: 0.5, high: 1), unit: FieldUnit = .none,
                choice: SliceChoice = .axis(.xy), hasOwnPlane: Bool = false, isCoarse: Bool = false,
                failure: String? = nil) -> FieldLegend {
        FieldLegend(range: range, unit: unit, isCoarse: isCoarse, usesUnitRange: false, choice: choice, hasOwnPlane: hasOwnPlane,
                    failure: failure)
    }

    @Test func numbersHaveAtMostThreeSignificantDigitsAndTheMessageLocale() {
        #expect(FieldLegend.text(0.5, unit: .none) == "0.5")
        #expect(FieldLegend.text(1234.5678, unit: .none) == "1,230")
        #expect(FieldLegend.text(12.3456, unit: .none) == "12.3")
        #expect(FieldLegend.text(0.000_123_4, unit: .none) == "0.000123")
        #expect(FieldLegend.text(10, unit: .none) == "10")
    }

    @Test func zeroIsNeverMinusZeroAndMillimetresAreSaid() {
        #expect(FieldLegend.text(-0.0, unit: .none) == "0" && FieldLegend.text(0, unit: .millimetres) == "0 mm")
        #expect(FieldLegend.text(-12.34, unit: .millimetres) == "-12.3 mm")
    }

    @Test func theThreeLabelsAreTheRangesEndsAndMiddle() {
        let labels = legend(FieldPreviewRange(low: -14.5, mid: 0, high: 14.5), unit: .millimetres).labels
        #expect(labels == FieldLegend.Labels(low: "-14.5 mm", mid: "0 mm", high: "14.5 mm"))
        #expect(legend(nil).labels == nil)
    }

    @Test func theSliceButtonsAreThePlaneWhenTheFieldHasOneThenTheAxesThenOff() {
        #expect(legend().sliceOptions.map(\.title) == ["XY", "YZ", "XZ", "Off"])
        #expect(legend(hasOwnPlane: true).sliceOptions.map(\.title) == ["Plane", "XY", "YZ", "XZ", "Off"])
        #expect(legend(hasOwnPlane: true).sliceOptions.map(\.choice) == [.own, .axis(.xy), .axis(.yz), .axis(.xz), .hidden])
    }

    @Test func theSelectedButtonIsTheOneTheChoiceNames() {
        #expect(legend(choice: .axis(.yz)).selectedOption == 1)
        #expect(legend(choice: .axis(.yz), hasOwnPlane: true).selectedOption == 2)
        #expect(legend(choice: .hidden).selectedOption == 3)
        #expect(legend(choice: .own, hasOwnPlane: true).selectedOption == 0)
        #expect(legend(choice: .own).selectedOption == nil, "no plane of its own: nothing to select")
    }

    @Test func theNotesAreTheCoarseWarningAndTheKernelsWords() {
        #expect(legend().notes.isEmpty)
        #expect(legend(isCoarse: true).notes == ["Preview sampled coarsely"])
        #expect(legend(failure: "A selected face doesn't exist on the solid.").notes == ["A selected face doesn't exist on the solid."])
        #expect(legend(isCoarse: true, failure: "No.").notes == ["No.", "Preview sampled coarsely"])
    }
}
