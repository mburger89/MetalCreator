import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

@MainActor
@Suite("Zebra band")
struct ZebraBandTests {
    static let right = Vector3(1, 0, 0)
    static let up = Vector3(0, 1, 0)
    static let back = Vector3(0, 0, 1)

    static func zebra(_ direction: ViewportZebra.Direction = .horizontal, count: Int = 12, share: Double = 0.5) -> ViewportZebra {
        ViewportZebra(direction: direction, stripes: count, blackShare: share)
    }

    /// A normal tilted by `angle` from `back` towards `towards`, seen from `back`.
    static func band(angle: Double, towards: Vector3, zebra: ViewportZebra) -> Double {
        let normal = back * cos(angle) + towards * sin(angle)
        return ZebraBand.value(normal: normal, toEye: back, right: right, up: up, back: back, zebra: zebra)
    }

    @Test func aMirrorFacingTheEyeIsAtPhaseZero() {
        let value = ZebraBand.value(normal: Self.back, toEye: Self.back, right: Self.right, up: Self.up, back: Self.back,
                                    zebra: Self.zebra(share: 0.3))
        #expect(value == 0)
    }

    @Test func countPeriodsOverTheFullTurn() {
        // The reflection turns by twice the normal's tilt, so a tilt of -pi/2...pi/2 covers the reflection's full turn.
        let count = 8
        let zebra = Self.zebra(count: count)
        let steps = 20_000
        var changes = 0
        var previous: Double?
        for step in 0..<steps {
            let tilt = -Double.pi / 2 + (Double(step) + 0.5) / Double(steps) * Double.pi
            let value = Self.band(angle: tilt, towards: Self.up, zebra: zebra)
            if let previous, previous != value { changes += 1 }
            previous = value
        }
        #expect(changes == 2 * count || changes == 2 * count - 1 || changes == 2 * count + 1)
    }

    @Test(arguments: [0.2, 0.5, 0.8])
    func blackShareSetsTheDutyCycle(share: Double) {
        let zebra = Self.zebra(count: 10, share: share)
        let steps = 40_000
        var black = 0
        for step in 0..<steps {
            let tilt = -Double.pi / 2 + (Double(step) + 0.5) / Double(steps) * Double.pi
            if Self.band(angle: tilt, towards: Self.up, zebra: zebra) == 0 { black += 1 }
        }
        #expect(abs(Double(black) / Double(steps) - share) < 0.01)
    }

    @Test func verticalUsesTheRightAxis() {
        let horizontal = Self.zebra(.horizontal)
        let vertical = Self.zebra(.vertical)
        // Tilted towards the right: only the vertical zebra sees the angle; horizontal stays at phase 0 (black).
        let tilt = 0.4
        let normal = Self.back * cos(tilt) + Self.right * sin(tilt)
        func value(_ zebra: ViewportZebra) -> Double {
            ZebraBand.value(normal: normal, toEye: Self.back, right: Self.right, up: Self.up, back: Self.back, zebra: zebra)
        }
        #expect(value(horizontal) == 0)
        #expect(value(vertical) == Self.band(angle: tilt, towards: Self.up, zebra: horizontal))
        #expect(value(vertical) == 1)
    }

    @Test func aNegativePhaseUsesTheFractionBelowIt() {
        // theta = -0.01 rad over 12 stripes: p slightly negative, fract close to 1: white.
        let value = Self.band(angle: -0.005, towards: Self.up, zebra: Self.zebra(share: 0.5))
        #expect(value == 1)
    }

    @Test func showZebraChangesTheRenderKey() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        let before = model.renderKey
        model.showZebra(Self.zebra())
        #expect(model.renderKey != before)
        #expect(model.zebra == Self.zebra())
    }

    @Test func anEqualZebraDoesNot() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.showZebra(Self.zebra())
        let key = model.renderKey
        model.showZebra(Self.zebra())
        #expect(model.renderKey == key)
    }

    @Test func theUniformsCarryTheLockAndSettings() {
        let free = ZebraUniforms(Self.zebra(.vertical, count: 7, share: 0.25))
        #expect(free.params == SIMD4<Float>(7, 0.25, 1, 0))
        #expect(free.toEye == SIMD4<Float>(0, 0, 1, 0))
        var locked = Self.zebra()
        locked.lock = .init(right: Vector3(0, 1, 0), up: Vector3(0, 0, 1), toEye: Vector3(1, 0, 0))
        let uniforms = ZebraUniforms(locked)
        #expect(uniforms.right == SIMD4<Float>(0, 1, 0, 0))
        #expect(uniforms.toEye == SIMD4<Float>(1, 0, 0, 0))
        #expect(uniforms.params.w == 1)
    }
}
