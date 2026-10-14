import Foundation

/// Smooth fractal gradient noise in 0…1 (fields spec §3.1): 3D simplex noise (Gustavson, "Simplex noise demystified"), summed
/// over `octaves` that each halve in size and amplitude, rescaled from about −1…1 to 0…1. The gradient at each lattice corner is
/// picked by hashing the corner with `SeededRandom` (SplitMix64, purpose `.fieldNoise`, the octave as the stream), never the
/// system's generator, so a seed gives the same field on every machine and release. A value depends on the point and the
/// settings alone, never on which other points are sampled with it. At the origin every octave is 0, so the value is exactly
/// 0.5 whatever the seed.
public struct FieldNoise: Sendable {
    public let scale: Double
    public let octaves: Int
    private let generators: [SeededRandom]

    /// `scale` is the size in mm of the first octave's features; `octaves` is 1 or more.
    public init(seed: Int, scale: Double, octaves: Int) {
        precondition(octaves >= 1 && scale > 0, "FieldNoise needs 1 or more octaves and a scale above 0")
        self.scale = scale
        self.octaves = octaves
        self.generators = (0..<octaves).map { SeededRandom(seed: seed, stream: $0, purpose: .fieldNoise) }
    }

    /// The noise at `point`, in 0…1.
    public func value(at point: Vector3) -> Double {
        var sum = 0.0
        var total = 0.0
        var amplitude = 1.0
        var size = scale
        for generator in generators {
            sum += amplitude * Self.simplex(point.x / size, point.y / size, point.z / size, generator)
            total += amplitude
            amplitude *= 0.5
            size *= 0.5
        }
        return min(1, max(0, (sum / total + 1) / 2))
    }

    private static let skew = 1.0 / 3.0
    private static let unskew = 1.0 / 6.0

    /// The twelve edge-midpoint gradients of a cube.
    private static let gradients: [(Double, Double, Double)] = [
        (1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0), (1, 0, 1), (-1, 0, 1),
        (1, 0, -1), (-1, 0, -1), (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1),
    ]

    /// The four corners of the simplex a point can lie in, as steps from the base corner, for each of the six orderings of
    /// the point's offsets.
    private static let corners: [[(Int, Int, Int)]] = [
        [(0, 0, 0), (1, 0, 0), (1, 1, 0), (1, 1, 1)],
        [(0, 0, 0), (1, 0, 0), (1, 0, 1), (1, 1, 1)],
        [(0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1)],
        [(0, 0, 0), (0, 0, 1), (0, 1, 1), (1, 1, 1)],
        [(0, 0, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)],
        [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 1, 1)],
    ]

    /// One octave of 3D simplex noise at (x, y, z), about −1…1.
    private static func simplex(_ x: Double, _ y: Double, _ z: Double, _ random: SeededRandom) -> Double {
        let skewed = (x + y + z) * skew
        let (i, j, k) = (lattice(x + skewed), lattice(y + skewed), lattice(z + skewed))
        let back = Double(i + j + k) * unskew
        let (x0, y0, z0) = (x - (Double(i) - back), y - (Double(j) - back), z - (Double(k) - back))
        let ordering: Int
        if x0 >= y0 {
            ordering = y0 >= z0 ? 0 : (x0 >= z0 ? 1 : 2)
        } else {
            ordering = y0 < z0 ? 3 : (x0 < z0 ? 4 : 5)
        }
        var sum = 0.0
        for (step, corner) in corners[ordering].enumerated() {
            let shift = Double(step) * unskew
            let (dx, dy, dz) = (x0 - Double(corner.0) + shift, y0 - Double(corner.1) + shift, z0 - Double(corner.2) + shift)
            let falloff = 0.6 - dx * dx - dy * dy - dz * dz
            guard falloff > 0 else { continue }
            let gradient = gradient(i + corner.0, j + corner.1, k + corner.2, random)
            let weight = falloff * falloff
            sum += weight * weight * (gradient.0 * dx + gradient.1 * dy + gradient.2 * dz)
        }
        return 32 * sum
    }

    /// `value` floored to a lattice index, held to a range an `Int` (and the packing below) can take.
    private static func lattice(_ value: Double) -> Int {
        Int(max(-1e15, min(1e15, value.rounded(.down))))
    }

    /// The gradient of a lattice corner: the corner packed into 63 bits (21 per axis, so corners 2 million cells apart repeat),
    /// hashed by the generator's draw at that index.
    private static func gradient(_ i: Int, _ j: Int, _ k: Int, _ random: SeededRandom) -> (Double, Double, Double) {
        let packed = (i & 0x1F_FFFF) << 42 | (j & 0x1F_FFFF) << 21 | (k & 0x1F_FFFF)
        return gradients[Int(random.value(at: packed) >> 33) % gradients.count]
    }
}
