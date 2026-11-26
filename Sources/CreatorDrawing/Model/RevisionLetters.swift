/// Revision letters (DR-5 R8): ASME Y14.35's A to Y without I, O, Q, S, X and Z, then AA, AB, ... from the same twenty.
public enum RevisionLetters {
    private static let alphabet: [Character] = Array("ABCDEFGHJKLMNPRTUVWY")

    public static func letter(at index: Int) -> String {
        var n = max(index, 0) + 1
        var result: [Character] = []
        while n > 0 {
            n -= 1
            result.append(alphabet[n % alphabet.count])
            n /= alphabet.count
        }
        return String(result.reversed())
    }

    /// Whether the text is made only of the twenty letters (and not empty).
    public static func isValid(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { alphabet.contains($0) }
    }

    /// The letter after the last row whose letter is valid, else "A".
    public static func next(after rows: [RevisionRow]) -> String {
        guard let last = rows.last(where: { isValid($0.letter) }) else { return "A" }
        var index = 0
        for character in last.letter { index = index * alphabet.count + (alphabet.firstIndex(of: character) ?? 0) + 1 }
        // `index` is the 1-based position of the letter in the bijective numbering, so it is also the next 0-based index.
        return letter(at: index)
    }
}
