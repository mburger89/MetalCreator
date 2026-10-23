/// How `ImplicitCompiler.Generator` spells what differs between Metal and HLSL (plan xp-c): a float parameter, an integer parameter, and the
/// environment argument the library's functions take in MSL (`e`, the buffers) and do not in HLSL (the buffers are globals). Everything else the
/// generator writes is the same text in both.
enum ShaderDialect: Sendable {
    case msl
    case hlsl

    func parameter(_ slot: Int) -> String {
        switch self {
        case .msl: "e.P[\(slot)]"
        case .hlsl: "P(\(slot))"
        }
    }

    func integer(_ slot: Int) -> String {
        switch self {
        case .msl: "e.I[\(slot)]"
        case .hlsl: "I(\(slot))"
        }
    }

    /// Written first in a library call's arguments.
    var environment: String {
        switch self {
        case .msl: "e, "
        case .hlsl: ""
        }
    }
}
