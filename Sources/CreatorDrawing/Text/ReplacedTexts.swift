/// The typed texts a sheet's lettering had to replace (plan R13), shared by the PDF and DXF writers.
public enum ReplacedTexts {
    /// The distinct `original`s of the texts whose run has replacements, in first-seen order.
    public static func collect(_ texts: [SheetText]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for text in texts where text.run.hasReplacements && seen.insert(text.original).inserted {
            result.append(text.original)
        }
        return result
    }
}
