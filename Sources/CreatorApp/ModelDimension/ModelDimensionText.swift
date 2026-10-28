/// The words of the model dimension tool.
enum ModelDimensionText {
    /// The chip when the two picks share no sketch (spec §3.5).
    static let differentFeatures = "These come from different features: a measurement tool is planned"

    /// The banner's prompt: what to do and how many are picked.
    static func prompt(picked: Int) -> String {
        "Click two edges or holes to dimension · \(picked) picked"
    }
}
