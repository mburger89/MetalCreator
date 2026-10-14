import CreatorGeometry
import Foundation

/// How fast a field changes (implicit spec §3.3). `value` is in field units per millimetre.
public struct FieldSlope: Hashable, Sendable {
    public var value: Double
    /// False when some part of the field has no bound, and `value` is `Field.unknownSlope` or more.
    public var isKnown: Bool

    public init(value: Double, isKnown: Bool = true) {
        self.value = value
        self.isKnown = isKnown
    }
}

extension Field {
    /// What an unknown bound is taken as, per millimetre, and what the node that used it warns about ("the preview may be slow").
    public static let unknownSlope = 10.0

    /// A conservative bound on |f(a) − f(b)| ÷ |a − b|: analytic for distance, linear and radial sources, a declared bound for noise
    /// (`FieldNoise.unitSlope`), finite differences over the pixels of an image, the bound of an implicit solid for an implicit, and
    /// the usual rules for the maths: sums add, a product weighs each side's slope by the other's largest value, a remap scales by its
    /// range ratio, an extremum or a clamp keeps the larger. A product with a side of unknown range, or a part with no bound, makes
    /// the whole bound unknown, and then it is at least `unknownSlope`.
    public var slopeBound: FieldSlope { slopeBound(distanceSlope: { _, _ in 1 }) }

    /// `slopeBound` with each distance leaf's slope given by `distanceSlope` instead of the exact distance's 1: a baked grid
    /// interpolates trilinearly and can be steeper, and a gain on the field scales that steepness.
    public func slopeBound(distanceSlope: (DistanceSource, Bool) -> Double) -> FieldSlope {
        let bound = slope(distanceSlope)
        return bound.known ? FieldSlope(value: bound.value) : FieldSlope(value: max(bound.value, Self.unknownSlope), isKnown: false)
    }

    /// Every value the field can take, or `nil` when that is unbounded or unknown. A distance, a gradient or a product of such has no
    /// range; noise and images are in 0…1.
    public var valueRange: ClosedRange<Double>? {
        switch self {
        case .constant(let value):
            return value...value
        case .distance, .linearGradient, .radialGradient, .implicit:
            return nil
        case .noise, .image:
            return 0...1
        case .add(let a, let b):
            guard let x = a.valueRange, let y = b.valueRange else { return nil }
            return (x.lowerBound + y.lowerBound)...(x.upperBound + y.upperBound)
        case .multiply(let a, let b):
            guard let x = a.valueRange, let y = b.valueRange else { return nil }
            let products = [x.lowerBound * y.lowerBound, x.lowerBound * y.upperBound, x.upperBound * y.lowerBound,
                            x.upperBound * y.upperBound,
            ]
            guard let low = products.min(), let high = products.max() else { return nil }
            return low...high
        case .minimum(let a, let b):
            guard let x = a.valueRange, let y = b.valueRange else { return nil }
            return min(x.lowerBound, y.lowerBound)...min(x.upperBound, y.upperBound)
        case .maximum(let a, let b):
            guard let x = a.valueRange, let y = b.valueRange else { return nil }
            return max(x.lowerBound, y.lowerBound)...max(x.upperBound, y.upperBound)
        case .smoothMinimum(let a, let b, let width):
            guard let x = a.valueRange, let y = b.valueRange else { return nil }
            return (min(x.lowerBound, y.lowerBound) - max(width, 0) / 4)...min(x.upperBound, y.upperBound)
        case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
            if clamped { return min(toLow, toHigh)...max(toLow, toHigh) }
            guard let range = inner.valueRange, fromHigh != fromLow else { return fromHigh == fromLow ? toLow...toLow : nil }
            let ends = [range.lowerBound, range.upperBound].map { toLow + ($0 - fromLow) / (fromHigh - fromLow) * (toHigh - toLow) }
            guard let low = ends.min(), let high = ends.max() else { return nil }
            return low...high
        case .clamp(_, let low, let high):
            return low...high
        }
    }

    // The slope with a flag for "some part had no bound". One branch per case, with no `default`. A new case is a compile error.
    // swiftlint:disable:next cyclomatic_complexity
    private func slope(_ leaf: (DistanceSource, Bool) -> Double) -> (value: Double, known: Bool) {
        switch self {
        case .constant:
            return (0, true)
        case .distance(let source, let signed):
            return (leaf(source, signed), true)
        case .linearGradient(_, let length):
            return (1 / abs(length), true)
        case .radialGradient(_, let radius):
            return (1 / abs(radius), true)
        case .noise(_, let scale, let octaves):
            return (FieldNoise.slopeBound(scale: scale, octaves: octaves), true)
        case .image(let image, _, let width, let height, let edges):
            return (image.slopeBound(width: width, height: height, edges: edges), true)
        case .implicit(let solid):
            return (solid.payload.lipschitz, true)
        case .add(let a, let b):
            let (x, y) = (a.slope(leaf), b.slope(leaf))
            return (x.value + y.value, x.known && y.known)
        case .multiply(let a, let b):
            let (x, y) = (a.slope(leaf), b.slope(leaf))
            guard let rangeA = a.valueRange, let rangeB = b.valueRange else { return (x.value + y.value, false) }
            let (largestA, largestB) = (max(abs(rangeA.lowerBound), abs(rangeA.upperBound)),
                                        max(abs(rangeB.lowerBound), abs(rangeB.upperBound)))
            return (largestB * x.value + largestA * y.value, x.known && y.known)
        case .minimum(let a, let b), .maximum(let a, let b), .smoothMinimum(let a, let b, _):
            let (x, y) = (a.slope(leaf), b.slope(leaf))
            return (max(x.value, y.value), x.known && y.known)
        case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, _):
            let slope = inner.slope(leaf)
            guard fromHigh != fromLow else { return (0, true) }
            return (slope.value * abs((toHigh - toLow) / (fromHigh - fromLow)), slope.known)
        case .clamp(let inner, _, _):
            return inner.slope(leaf)
        }
    }
}

extension GreyImage {
    /// A bound on how fast the picture's grey changes over the field's rectangle, in value per millimetre: bilinear interpolation
    /// has each gradient component at most the largest difference of neighbouring pixels along that axis over the pixel size, so the
    /// bound is the length of the two. A tiling picture also counts the step from its last pixel back to its first.
    func slopeBound(width: Double, height: Double, edges: ImageEdges) -> Double {
        var across: UInt16 = 0, down: UInt16 = 0
        for row in 0..<self.height {
            for column in 0..<self.width {
                let here = pixels[row * self.width + column]
                let right = column + 1 < self.width ? pixels[row * self.width + column + 1]
                    : (edges == .tile ? pixels[row * self.width] : here)
                let below = row + 1 < self.height ? pixels[(row + 1) * self.width + column]
                    : (edges == .tile ? pixels[column] : here)
                across = max(across, here > right ? here - right : right - here)
                down = max(down, here > below ? here - below : below - here)
            }
        }
        let perMillimetreX = Double(across) / 65_535 / (abs(width) / Double(self.width))
        let perMillimetreY = Double(down) / 65_535 / (abs(height) / Double(self.height))
        return (perMillimetreX * perMillimetreX + perMillimetreY * perMillimetreY).squareRoot()
    }
}
