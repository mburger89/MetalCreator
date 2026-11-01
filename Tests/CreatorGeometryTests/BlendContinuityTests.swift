import Foundation
import Testing
@testable import CreatorGeometry

@Suite("BlendContinuity")
struct BlendContinuityTests {
    private func formula(_ continuity: BlendContinuity, _ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = max(k - abs(a - b), 0) / k
        switch continuity {
        case .g1: return min(a, b) - h * h * k / 4
        case .g2: return min(a, b) - h * h * h * k / 6
        case .g3: return min(a, b) - h * h * h * h * (h * h - 6 * h + 10) * k / 32
        }
    }

    @Test(arguments: BlendContinuity.allCases)
    func eachContinuityMatchesItsFormula(_ continuity: BlendContinuity) {
        for i in 0..<20 {
            let a = Double(i) * 0.37 - 3
            let b = Double((i * 7) % 11) * 0.21 - 1
            let k = 0.5 + Double(i % 5)
            let got = FieldMath.smoothMinimum(a, b, width: k, continuity: continuity)
            #expect(abs(got - formula(continuity, a, b, k)) < 1e-12)
        }
    }

    @Test(arguments: BlendContinuity.allCases)
    func zeroWidthIsMin(_ continuity: BlendContinuity) {
        #expect(FieldMath.smoothMinimum(1.5, -2, width: 0, continuity: continuity) == -2)
        #expect(FieldMath.smoothMinimum(0.25, 0.25, width: 0, continuity: continuity) == 0.25)
    }

    @Test func defaultIsG1() {
        #expect(FieldMath.smoothMinimum(1, 1.2, width: 1) == FieldMath.smoothMinimum(1, 1.2, width: 1, continuity: .g1))
    }

    /// The dip leaves the plain minimum to its order at the blend's edge: dip(ε)/εⁿ → 0 for the continuity's order n (G1 C1, G2
    /// C2, G3 C3) while the next power's ratio is the polynomial's leading coefficient (1/4, 1/6, 5/16).
    @Test func continuityAtTheBlendEdge() {
        let eps = 1e-3
        func ratio(_ continuity: BlendContinuity, power: Int) -> Double {
            // a − b = k·(1 − ε): ε inside the blend.
            let a = 1 - eps, b = 0.0
            let dip = min(a, b) - FieldMath.smoothMinimum(a, b, width: 1, continuity: continuity)
            return dip / pow(eps, Double(power))
        }
        #expect(ratio(.g1, power: 1) < 1e-3)
        #expect(ratio(.g2, power: 2) < 1e-3)
        #expect(ratio(.g3, power: 3) < 1e-3)
        #expect(abs(ratio(.g1, power: 2) - 0.25) < 1e-3)
        #expect(abs(ratio(.g2, power: 3) - 1.0 / 6) < 1e-3)
        #expect(abs(ratio(.g3, power: 4) - 5.0 / 16) < 1e-2)
        // Outside the blend the value is the plain minimum.
        for continuity in BlendContinuity.allCases {
            #expect(FieldMath.smoothMinimum(1.5, 0, width: 1, continuity: continuity) == 0)
        }
    }

    /// At a = b the plain minimum has a kink; the smooth one is even in a − b, so it is differentiable there to its order exactly
    /// when the odd-order one-sided derivatives vanish: no s term for G1, G2 and no s or s³ term for G3.
    @Test func smoothAtEquality() {
        let eps = 1e-3
        func rise(_ continuity: BlendContinuity, _ t: Double) -> Double {
            FieldMath.smoothMinimum(t / 2, -t / 2, width: 1, continuity: continuity)
                - FieldMath.smoothMinimum(0, 0, width: 1, continuity: continuity)
        }
        for continuity in BlendContinuity.allCases {
            #expect(abs(rise(continuity, eps) / eps) < 1e-3, "\(continuity.label): first derivative")
        }
        // Fit c2 t² + c4 t⁴ from two steps: a cubic term would leave a remainder of order t³.
        let g3 = BlendContinuity.g3
        let remainder = rise(g3, 2 * eps) - 4 * rise(g3, eps)
        #expect(abs(remainder / pow(eps, 3)) < 1e-2, "G3: third derivative")
    }

    @Test func deepestDipIsAtEquality() {
        let expected: [BlendContinuity: Double] = [.g1: 0.25, .g2: 1.0 / 6, .g3: 5.0 / 32]
        for continuity in BlendContinuity.allCases {
            let k = 2.0
            let equal = 2.0 - FieldMath.smoothMinimum(2, 2, width: k, continuity: continuity)
            #expect(abs(equal - k * (expected[continuity] ?? 0)) < 1e-12)
            for step in 1...20 {
                let gap = Double(step) * 0.1
                #expect(2.0 - FieldMath.smoothMinimum(2, 2 + gap, width: k, continuity: continuity) <= equal + 1e-12)
            }
        }
    }

    @Test(arguments: BlendContinuity.allCases)
    func dipSlopeBoundsTheSampledSlope(_ continuity: BlendContinuity) {
        var largest = 0.0
        let step = 1e-6
        for i in 0...100 {
            let gap = Double(i) / 100
            let up = continuity.dip(width: 1 + step, gap: gap)
            let down = continuity.dip(width: 1 - step, gap: gap)
            largest = max(largest, abs(up - down) / (2 * step))
        }
        #expect(largest <= continuity.dipSlope + 1e-6)
        #expect(largest >= continuity.dipSlope * 0.99)
    }

    @Test func dipSlopeIsPinned() {
        #expect(BlendContinuity.g1.dipSlope == 0.25)
        #expect(BlendContinuity.g2.dipSlope == 1.0 / 6.0)
        #expect(BlendContinuity.g3.dipSlope == 5.0 / 32.0)
        #expect(BlendContinuity.allCases.map(\.label) == ["G1", "G2", "G3"])
        #expect(BlendContinuity.allCases.map(\.rawValue) == [0, 1, 2])
    }
}
