/// A value in `colors`: text, or anything else (kept apart so an unknown role's value never fails the file).
enum ThemeFileColor: Codable, Equatable {
    case text(String)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = (try? container.decode(String.self)).map(ThemeFileColor.text) ?? .other
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .other: try container.encodeNil()
        }
    }
}
