/// Why the viewport's GPU objects could not be made.
enum ViewportRenderError: Error, CustomStringConvertible {
    case missingShader(String)
    case deviceRefused(String)

    var description: String {
        switch self {
        case .missingShader(let name): "The viewport shader \(name) is missing."
        case .deviceRefused(let what): "The GPU could not create \(what)."
        }
    }
}
