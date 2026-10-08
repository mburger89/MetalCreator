import Foundation

extension Int {
    /// A whole number inside a message, grouped the same way on every machine ("10,000").
    var display: String { formatted(.number.locale(.messages)) }
}
