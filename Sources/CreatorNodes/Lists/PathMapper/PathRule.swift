/// A Path Mapper rule, `source → target` (7a spec §4): `{A;B}` binds letters to indices, and the target computes where each item goes.
/// The number of letters in the source picks one of two forms.
///
/// Branch level: the source has as many letters as the tree has levels of branches and names branches; the target computes the
/// indices of the branch each whole branch goes to.
///
///     {A;B} → {A}         merge each row
///     {A;B} → {A;B%2}     fold the columns into two
///     {A} → {(i)}         each item goes to the branch of its own index in its branch
///
/// Item level: the source has one letter more than the tree has levels of branches, and the last letter is the item's position in
/// its branch. The target has the branch's terms (the items keep their order) or one more, the position in the branch it goes to.
///
///     {A;B} → {B;A}       on a 3 × 8 grid (3 branches of 8 items), transpose it into 8 × 3
///
/// A path names a branch with one index per level of branches, so a tree of 3 × 8 has the branches `{0}`, `{1}` and
/// `{2}`; a flat list has one branch, `{}`. Letters are single letters (not `i`) and bind the index at that level; a
/// letter repeated in the source must see the same index each time; a whole number in the source matches only that
/// index. `(i)` is an item's index within its branch. The target may use `+ − × / %` (`-`, `*` also), whole numbers,
/// letters and brackets.
struct PathRule: Equatable, Sendable {
    /// One level of the source path: a letter to bind, or an index to match.
    enum SourceTerm: Equatable, Sendable {
        case letter(Character)
        case index(Int)
    }

    /// One level of the target path, with its text in the rule for messages.
    struct TargetTerm: Equatable, Sendable {
        var expression: PathExpression
        var text: String
    }

    var source: [SourceTerm]
    var target: [TargetTerm]
    /// The source as written, for messages.
    var sourceText: String
    /// The target as written, for messages.
    var targetText: String

    var usesItemIndex: Bool { target.contains { $0.expression.usesItemIndex } }

    /// The letters the source binds, in order.
    var boundLetters: [Character] {
        source.compactMap { if case .letter(let letter) = $0 { letter } else { nil } }
    }
}
