import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Reads a `curve` socket's sources as curves: a wired curve passes through, a profile gives a curve per loop.
enum CurveInput {
    enum Holes {
        /// A profile with holes is refused with this message.
        case refuse(String)
        /// Every loop, outer first, becomes a curve.
        case all
    }

    static func loops(_ sources: [CurveSource], holes: Holes, kernel: any Kernel, tag: NodeTag) async throws -> [Curve] {
        var curves: [Curve] = []
        for source in sources {
            switch source {
            case .curve(let curve):
                curves.append(curve)
            case .profile(let profile):
                if case .refuse(let message) = holes, !profile.holes.isEmpty { throw NodeError.invalidValue(message) }
                for loop in profile.loops {
                    curves.append(try await kernel.makeCurve(CurvePiece.pieces(of: loop, on: profile.plane), tag: tag))
                }
            }
        }
        return curves
    }
}
