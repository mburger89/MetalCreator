/// Why a Path Mapper rule can't be read or applied. The message names the failing part of the rule, in plain words.
struct PathRuleError: Error, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}
