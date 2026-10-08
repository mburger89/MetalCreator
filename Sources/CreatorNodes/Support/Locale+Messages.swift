import Foundation

extension Locale {
    /// The locale for numbers and lists inside node messages. Pinned so messages (and the tests
    /// that assert them) read "1,000" and "2.5" on every machine. Messages are English until the
    /// app has a string catalog; switch this to the user's locale then.
    static let messages = Locale(identifier: "en_US")
}
