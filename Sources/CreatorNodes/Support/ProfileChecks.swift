import CreatorGraph

/// Shared validation for profile sizes, with messages that name the socket.
enum ProfileChecks {
    static func positive(_ value: Double, _ name: SocketName) throws {
        guard value.isFinite, value > 0 else {
            throw NodeError.invalidValue("“\(name)” must be greater than 0 mm.")
        }
    }
}
