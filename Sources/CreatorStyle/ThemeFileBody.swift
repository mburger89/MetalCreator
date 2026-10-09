/// The file's JSON object. Unknown top-level keys are ignored by `Decodable`.
struct ThemeFileBody: Codable {
    var version: Int
    var name: String?
    var dark: Bool?
    var colors: [String: ThemeFileColor]
}
