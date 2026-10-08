import Foundation

extension Double {
    /// Up to two decimals, for numbers inside messages ("12.5", "3").
    var display: String { formatted(.number.precision(.fractionLength(0...2)).locale(.messages)) }
}
