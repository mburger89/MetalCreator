import Foundation
import CreatorGeometry

/// The five triply periodic minimal surfaces of the TPMS lattice (implicit spec §3.4), each by its standard trigonometric
/// approximation g(q) = 0 with q in radians, period 2π on every axis. A cell of `a` millimetres has q = 2π p / a.
///
/// g is not a distance. Near its zero set a step of `h` in g is a step of about `h / |∇g|` radians, and |∇g| varies over the surface,
/// so each type has a `wallScale`: the mean of |∇g| over a thin shell about the surface. A wall `|g| < wallScale × t × π / a` then has
/// the mean thickness `t` to first order, which the tests pin (a gyroid's within 5%). `gradientBound` and `valueBound` are what the
/// lipschitz constant is made from; the tests check them against dense samples.
public enum TPMSType: Int, Hashable, Sendable, CaseIterable {
    case gyroid = 0
    case schwarzP = 1
    case diamond = 2
    case neovius = 3
    case lidinoid = 4

    /// The names the node's segmented control shows, in raw-value order.
    public static let options = ["Gyroid", "Schwarz P", "Diamond", "Neovius", "Lidinoid"]

    public var name: String { Self.options[rawValue] }

    /// g at `q` (radians).
    public func value(at q: Vector3) -> Double {
        let (sx, sy, sz) = (sin(q.x), sin(q.y), sin(q.z))
        let (cx, cy, cz) = (cos(q.x), cos(q.y), cos(q.z))
        switch self {
        case .gyroid:
            return sx * cy + sy * cz + sz * cx
        case .schwarzP:
            return cx + cy + cz
        case .diamond:
            return sx * sy * sz + sx * cy * cz + cx * sy * cz + cx * cy * sz
        case .neovius:
            return 3 * (cx + cy + cz) + 4 * cx * cy * cz
        case .lidinoid:
            let first = sin(2 * q.x) * cy * sz + sin(2 * q.y) * cz * sx + sin(2 * q.z) * cx * sy
            let second = cos(2 * q.x) * cos(2 * q.y) + cos(2 * q.y) * cos(2 * q.z) + cos(2 * q.z) * cos(2 * q.x)
            return 0.5 * first - 0.5 * second + 0.15
        }
    }

    /// The mean of |∇g| over a thin shell about g = 0, so that a wall `|g| ≤ wallScale × t × π / a` is `t` thick on average. Measured
    /// on a 300³ grid of one cell as the limit of shells |g| < 0.005 to 0.04 (the samples scatter by about 0.5%; a gyroid's surface area
    /// per a² from the same sum is 3.10, the literature's 3.09 to within the grid).
    public var wallScale: Double {
        switch self {
        case .gyroid: 1.53
        case .schwarzP: 1.31
        case .diamond: 1.49
        case .neovius: 2.57
        case .lidinoid: 1.28
        }
    }

    /// A bound on |∇g| over all q: the largest value found on a 160³ grid of one cell (1.732 for the gyroid, the P and the diamond,
    /// 7.00 for the Neovius, 2.60 for the Lidinoid) with 5% added.
    public var gradientBound: Double {
        switch self {
        case .gyroid, .schwarzP, .diamond: 1.82
        case .neovius: 7.35
        case .lidinoid: 2.73
        }
    }

    /// A bound on |g|: the P is exactly 3, the Neovius 13; the others from the same grid with a margin.
    public var valueBound: Double {
        switch self {
        case .gyroid: 1.5
        case .schwarzP: 3
        case .diamond: 1.42
        case .neovius: 13
        case .lidinoid: 1.35
        }
    }
}
