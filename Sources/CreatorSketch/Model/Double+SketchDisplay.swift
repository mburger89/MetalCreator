import Foundation

extension Double {
    /// Up to three decimals, the same on every machine ("30", "12.5"), for plain-language messages.
    var sketchDisplay: String {
        formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
