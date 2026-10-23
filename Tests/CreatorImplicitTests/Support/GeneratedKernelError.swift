/// A test precondition that failed loudly instead of passing vacuously: a fixture the HLSL generator refuses (plan xp-c, Review Focus 1): the failure names the fixture.
enum GeneratedKernelError: Error, CustomStringConvertible {
    case refused(fixture: String, reason: String)
    case backendNotReady(String)

    var description: String {
        switch self {
        case .refused(let fixture, let reason): "the HLSL generator refused the fixture \"\(fixture)\": \(reason)"
        case .backendNotReady(let reason): "the SDL_GPU backend is not ready: \(reason)"
        }
    }
}
