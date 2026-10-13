import CreatorGraph
import CreatorKernel
import Foundation

extension FieldLegend {
    /// The numbers under the ramp: its low end, its middle and its high end.
    struct Labels: Equatable {
        var low: String
        var mid: String
        var high: String
    }

    /// One of the slice buttons.
    struct SliceOption: Equatable {
        var title: String
        var choice: SliceChoice
    }

    /// The ramp's three numbers, or `nil` before there is a range.
    var labels: Labels? {
        range.map { Labels(low: Self.text($0.low, unit: unit), mid: Self.text($0.mid, unit: unit), high: Self.text($0.high, unit: unit)) }
    }

    /// The slice buttons: Plane when the field has a plane of its own, the three axis planes, and Off.
    var sliceOptions: [SliceOption] {
        (hasOwnPlane ? [SliceOption(title: "Plane", choice: .own)] : [])
            + SliceAxis.allCases.map { SliceOption(title: $0.title, choice: .axis($0)) } + [SliceOption(title: "Off", choice: .hidden)]
    }

    /// The index in `sliceOptions` of the button the slice's choice names, or `nil` for none.
    var selectedOption: Int? { sliceOptions.firstIndex { $0.choice == choice } }

    /// The lines under the numbers: what went wrong, then the coarse-sampling notice (D14).
    var notes: [String] {
        (failure.map { [$0] } ?? []) + (isCoarse ? ["Preview sampled coarsely"] : [])
    }

    /// `value` with at most three significant digits in the message locale, "mm" after it for a distance, and never "-0".
    static func text(_ value: Double, unit: FieldUnit) -> String {
        let number = (value == 0 ? 0 : value).formatted(.number.precision(.significantDigits(1...3)).locale(.messages))
        return unit == .millimetres ? "\(number) mm" : number
    }
}
