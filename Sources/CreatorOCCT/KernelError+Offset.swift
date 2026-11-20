import CreatorKernel
import Foundation

extension KernelError {
    /// The 0.01 mm grid an offset search walks (R8).
    enum OffsetGrid {
        static let step = 0.01
        /// Most hundredths of a millimetre a search starts from, so a huge distance can't overflow `Int`.
        static let mostHundredths = 1_000_000

        /// The first count of hundredths at or above `size`: the search tries only counts below it.
        static func firstFailing(for size: Double) -> Int {
            guard size > 0 else { return 0 }
            return Int(min((size * 100 - 1e-9).rounded(.up), Double(mostHundredths)))
        }
    }

    /// An offset (or a thickening) that can't be made at `distance`. `largest` is the largest distance that works, as a magnitude whose
    /// sign is `distance`'s; nil when none was found, and then the sentence says even 0.01 mm fails when that was tried. Shared by
    /// Offset Surface and Thicken.
    static func offsetFailed(distance: Double, largest: Double?, thickening: Bool = false,
                             locale: Locale = .messages) -> KernelError {
        let sign = distance < 0 ? -1.0 : 1.0
        let verb = thickening ? "thickened" : "offset"
        let head = "The surface can't be \(verb) by \(distance.millimetreText(locale: locale)) mm"
        if let largest {
            return .invalidInput("\(head); the most that works is \((sign * largest).millimetreText(locale: locale)) mm.")
        }
        if OffsetGrid.firstFailing(for: abs(distance)) > 1 {
            return .invalidInput("\(head); even \((sign * OffsetGrid.step).millimetreText(locale: locale)) mm fails.")
        }
        return .invalidInput("\(head).")
    }
}
