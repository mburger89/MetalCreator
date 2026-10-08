/// The coding key for a sketch ID used as a dictionary key: the decimal raw value as a string
/// (and as an int), so `[SketchEntityID: …]` and friends encode as JSON objects.
struct IDKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ rawValue: Int) {
        stringValue = String(rawValue)
        intValue = rawValue
    }

    init?(stringValue: String) {
        guard let rawValue = Int(stringValue) else { return nil }
        self.init(rawValue)
    }

    init?(intValue: Int) {
        self.init(intValue)
    }
}
