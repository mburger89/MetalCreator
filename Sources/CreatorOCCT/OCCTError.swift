/// A failure reported by the OCCT shim, carrying OCCT's own message.
struct OCCTError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}
