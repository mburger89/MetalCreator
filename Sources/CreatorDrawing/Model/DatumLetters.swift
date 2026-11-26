import Foundation

/// Datum letters (plan R10): one or two capitals A to Z without I, O or Q, one set per drawing.
public enum DatumLetters {
    private static let allowed: Set<Character> = Set("ABCDEFGHJKLMNPRSTUVWXYZ")

    public static func isValid(_ letter: String) -> Bool {
        (1...2).contains(letter.count) && letter.allSatisfy { allowed.contains($0) }
    }

    /// The typed text uppercased and trimmed, or nil when it is no datum letter.
    public static func normalized(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // Judged before uppercasing: "ß" would become "SS" and "ﬀ" "FF".
        guard (1...2).contains(trimmed.count), trimmed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let letter = trimmed.uppercased()
        return isValid(letter) ? letter : nil
    }

    /// Every datum feature symbol's letter: sheets in order, then annotation order.
    public static func letters(in document: DrawingDocument) -> [String] {
        document.sheets.flatMap { sheet in
            sheet.annotations.compactMap { annotation -> String? in
                if case .datumFeature(let datum) = annotation.kind { datum.letter } else { nil }
            }
        }
    }

    /// The first letter of `ViewLetters`' sequence no datum symbol of the document carries.
    public static func next(in document: DrawingDocument) -> String {
        ViewLetters.next(avoiding: Set(letters(in: document)))
    }
}
