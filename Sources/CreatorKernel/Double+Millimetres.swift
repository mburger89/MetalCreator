import Foundation

extension Double {
    /// A size in millimetres for a message: up to two decimals, written in `locale` ("2.5" in `Locale.messages`, "2,5"
    /// in a German one). The one formatter behind every number in a kernel message, so a call site can't forget the locale.
    package func millimetreText(locale: Locale = .messages) -> String {
        formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}
