/// The letters of section, detail and auxiliary views (R7): A to Z without I, O and Q, then AA, AB, ...
public enum ViewLetters {
    private static let alphabet: [Character] = Array("ABCDEFGHJKLMNPRSTUVWXYZ")

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

    /// The first letter no view of the sheet uses.
    public static func next(on sheet: DrawingSheet) -> String {
        next(avoiding: Set(sheet.views.compactMap(\.letter)))
    }

    static func next(avoiding used: Set<String>) -> String {
        var index = 0
        while used.contains(letter(at: index)) { index += 1 }
        return letter(at: index)
    }
}
