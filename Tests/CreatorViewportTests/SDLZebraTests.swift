#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// Zebra stripes on SDL_GPU, the twin of `ViewportZebraRenderTests`. A sphere of radius 10 about the origin is seen in a 200-point view
/// (400 pixels, scale 2); orthographic it stands at 5 points per mm centred on (100, 100). `ZebraBand.value` is the CPU twin of the
/// shader that each test asks what a pixel should be.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLZebraTests {
    typealias Rig = SDLRenderRig
    static let radius = 10.0
    static let sphere = TestMeshes.sphere(radius: radius, segments: 96)
    static let bounds = BoundingBox(min: Vector3(-10, -10, -10), max: Vector3(10, 10, 10))
    static let orthographic = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                                         projection: .orthographic)
    static let perspective = CameraPose(target: .zero, distance: 60, yaw: 0, pitch: 0, projection: .perspective)
    static let horizontal = ViewportZebra(direction: .horizontal, stripes: 12, blackShare: 0.5)

    func frame(pose: CameraPose = orthographic, zebra: ViewportZebra? = horizontal, ghost: Bool = false,
               clip: ViewportClip? = nil) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: Self.sphere, pose: pose, size: RenderFixtures.size, bounds: Self.bounds)
        frame.items[0].isGhost = ghost
        frame.zebra = zebra
        frame.showsViewCube = false
        frame.clip = clip
        return frame
    }

    func isWhite(_ colour: [Int]) -> Bool {
        let palette = ViewportPalette.dracula
        let white = Double(palette.shadeLight.x) * 255 * 0.8
        let black = Double(palette.shadeDark.x) * 255 * 0.15
        return Double(colour[0]) > (white + black) / 2
    }

    struct Expectation { var white: Bool; var margin: Double }

    func sphereSample(_ x: Double, _ y: Double, perspective: Bool) -> (normal: Vector3, toEye: Vector3)? {
        let (ndcX, ndcY) = ((x - 100) / 100, (100 - y) / 100)
        if !perspective {
            let (vx, vy) = (ndcX * 20, ndcY * 20)
            let z2 = Self.radius * Self.radius - vx * vx - vy * vy
            guard z2 > 0 else { return nil }
            return (Vector3(vx, vy, z2.squareRoot()) * (1 / Self.radius), Vector3(0, 0, 1))
        }
        let tangent = tan(CameraPose.fieldOfView / 2)
        let eye = Vector3(0, 0, Self.perspective.distance)
        let direction = Vector3(ndcX * tangent, ndcY * tangent, -1)
        let a = direction.dot(direction), b = 2 * eye.dot(direction)
        let c = eye.dot(eye) - Self.radius * Self.radius
        let discriminant = b * b - 4 * a * c
        guard discriminant > 0 else { return nil }
        let s = (-b - discriminant.squareRoot()) / (2 * a)
        let hit = eye + direction * s
        let toViewer = direction * (-s)
        return (hit * (1 / Self.radius), toViewer * (1 / toViewer.length))
    }

    func expectation(_ sample: (normal: Vector3, toEye: Vector3), zebra: ViewportZebra = horizontal) -> Expectation {
        let white = ZebraBand.value(normal: sample.normal, toEye: sample.toEye, right: Vector3(1, 0, 0), up: Vector3(0, 1, 0),
                                    back: Vector3(0, 0, 1), zebra: zebra) > 0.5
        let n = sample.normal, v = sample.toEye
        let r = n * (2 * n.dot(v)) - v
        let theta = atan2(zebra.direction == .vertical ? r.x : r.y, r.z)
        let phase = theta * Double(zebra.stripes) / (2 * Double.pi)
        let fraction = phase - phase.rounded(.down)
        return Expectation(white: white, margin: min(abs(fraction - zebra.blackShare), fraction, 1 - fraction))
    }

    func changes(_ pixels: [UInt8], from: (Int, Int), to: (Int, Int), steps: Int) -> Int {
        var count = 0
        var last: Bool?
        for step in 0...steps {
            let x = from.0 + (to.0 - from.0) * step / steps, y = from.1 + (to.1 - from.1) * step / steps
            let white = isWhite(Rig.color(pixels, x, y))
            if let last, last != white { count += 1 }
            last = white
        }
        return count
    }

    func clearPixels(perspective: Bool, zebra: ViewportZebra = horizontal) -> [(x: Int, y: Int, white: Bool)] {
        var found: [(x: Int, y: Int, white: Bool)] = []
        for y in stride(from: 56, to: 144, by: 3) {
            for x in stride(from: 56, to: 144, by: 3) {
                guard let sample = sphereSample(Double(x), Double(y), perspective: perspective) else { continue }
                let e = expectation(sample, zebra: zebra)
                if e.margin > 0.18 { found.append((x, y, e.white)) }
            }
        }
        return found
    }

    func wrongCount(_ clear: [(x: Int, y: Int, white: Bool)], _ pixels: [UInt8]) -> Int {
        clear.filter { isWhite(Rig.color(pixels, $0.x, $0.y)) != $0.white }.count
    }

    @Test func aSphereIsStriped() async throws {
        let rig = try Rig()
        let pixels = try await rig.draw(frame())
        #expect(changes(pixels, from: (100, 56), to: (100, 144), steps: 88) >= 6)
        let clear = clearPixels(perspective: false)
        #expect(clear.count > 100)
        let wrong = wrongCount(clear, pixels)
        #expect(wrong * 50 < clear.count, "\(wrong) of \(clear.count) pixels disagree with the twin")
    }

    @Test func oddStripeCountsMatchTheTwin() async throws {
        let rig = try Rig()
        let odd = ViewportZebra(direction: .horizontal, stripes: 13, blackShare: 0.5)
        for (pose, isPerspective) in [(Self.orthographic, false), (Self.perspective, true)] {
            let pixels = try await rig.draw(frame(pose: pose, zebra: odd))
            let clear = clearPixels(perspective: isPerspective, zebra: odd).filter { abs($0.x - 100) < 35 && abs($0.y - 100) < 35 }
            let wrong = wrongCount(clear, pixels)
            #expect(clear.count > 100)
            #expect(wrong * 20 < clear.count, "perspective \(isPerspective): \(wrong) of \(clear.count)")
        }
    }

    @Test func aLockedZebraStaysPutWhenOrbiting() async throws {
        let rig = try Rig()
        let poseA = Self.orthographic
        var poseB = Self.orthographic
        poseB.yaw = 0.7
        poseB.pitch = 0.3
        let lock = ViewportZebra.Frame(right: poseA.right, up: poseA.up, toEye: poseA.toEye)
        let locked = ViewportZebra(direction: .horizontal, stripes: 12, blackShare: 0.5, lock: lock)
        let lockedB = try await rig.draw(frame(pose: poseB, zebra: locked))
        let unlockedB = try await rig.draw(frame(pose: poseB))
        var checked = 0
        var unlockedDiffers = 0
        for i in 0..<120 {
            let azimuth = -0.5 + 0.0175 * Double(i), polar = 1.5 + 0.03 * Double(i % 11)
            let normal = Vector3(sin(polar) * sin(azimuth), -sin(polar) * cos(azimuth), cos(polar))
            guard normal.dot(poseB.toEye) > 0.4, normal.dot(poseA.toEye) > 0.4 else { continue }
            let expected = expectation((normal: Vector3(normal.dot(lock.right), normal.dot(lock.up), normal.dot(lock.toEye)),
                                        toEye: Vector3(0, 0, 1)), zebra: locked)
            guard expected.margin > 0.18 else { continue }
            let point = normal * Self.radius
            let x = Int((100 + 5 * point.dot(poseB.right)).rounded()), y = Int((100 - 5 * point.dot(poseB.up)).rounded())
            #expect(isWhite(Rig.color(lockedB, x, y)) == expected.white, "point \(i) at \(x),\(y)")
            if isWhite(Rig.color(unlockedB, x, y)) != expected.white { unlockedDiffers += 1 }
            checked += 1
        }
        #expect(checked >= 8)
        #expect(unlockedDiffers >= 1, "unlocked, orbiting moves the stripes")
    }

    @Test func ghostsAreNotStriped() async throws {
        let rig = try Rig()
        let striped = try await rig.draw(frame(ghost: true))
        let plain = try await rig.draw(frame(zebra: nil, ghost: true))
        #expect(striped == plain)
    }

    @Test func theClipStillCutsAStripedPart() async throws {
        let rig = try Rig()
        let clip = ViewportClip(origin: .zero, normal: Vector3(0, -1, 0))
        let whole = try await rig.draw(frame())
        let cut = try await rig.draw(frame(clip: clip))
        #expect(cut != whole)
        let palette = ViewportPalette.dracula
        let fallback = (0..<3).map { channel -> Int in
            let light = [palette.shadeLight.x, palette.shadeLight.y, palette.shadeLight.z][channel]
            let dark = [palette.shadeDark.x, palette.shadeDark.y, palette.shadeDark.z][channel]
            return Int(((light + dark) / 2 * 0.55 * 255).rounded())
        }
        var checked = 0, wrong = 0, fallbackLike = 0
        for y in stride(from: 56, to: 146, by: 3) {
            for x in stride(from: 56, to: 146, by: 3) {
                guard let sample = sphereSample(Double(x), Double(y), perspective: false) else { continue }
                let flipped = Vector3(-sample.normal.x, -sample.normal.y, sample.normal.z)
                let e = expectation((normal: flipped, toEye: sample.toEye))
                guard e.margin > 0.1 else { continue }
                let c = Rig.color(cut, x, y)
                if isWhite(c) != e.white { wrong += 1 }
                if zip(c, fallback).allSatisfy({ abs($0 - $1) <= 6 }) { fallbackLike += 1 }
                checked += 1
            }
        }
        #expect(checked > 100)
        #expect(wrong * 25 < checked, "\(wrong) of \(checked) back-face pixels disagree with the twin")
        #expect(fallbackLike * 25 < checked, "\(fallbackLike) pixels are the darkened fallback")
    }

    @Test func aFlatFaceIsOneUniformBand() async throws {
        let rig = try Rig()
        let box = RenderFixtures.bounds
        let target = Vector3(0, 0, 15)
        var pose = RenderFixtures.front
        pose.pitch = 0.2
        let normal = Vector3(0, -1, 0)
        let view = Vector3(normal.dot(pose.right), normal.dot(pose.up), normal.dot(pose.toEye))
        let expected = expectation((normal: view, toEye: Vector3(0, 0, 1)))
        try #require(expected.margin > 0.05, "pitch 0.2 puts the face inside a band")
        var frame = TestFrames.frame(mesh: TestMeshes.box(box), pose: pose, size: RenderFixtures.size, bounds: box)
        frame.zebra = Self.horizontal
        frame.showsViewCube = false
        let pixels = try await rig.draw(frame)
        var colours: [[Int]] = []
        for z in stride(from: 6.0, through: 24.0, by: 3.0) {
            for x in stride(from: -3.0, through: 3.0, by: 2.0) {
                let point = Vector3(x, -10, z) - target
                colours.append(Rig.color(pixels, Int((100 + 5 * point.dot(pose.right)).rounded()),
                                         Int((100 - 5 * point.dot(pose.up)).rounded())))
            }
        }
        let first = colours[0]
        for c in colours {
            #expect(zip(c, first).allSatisfy { abs($0 - $1) <= 3 }, "uniform: \(c) against \(first)")
            #expect(isWhite(c) == expected.white)
        }
    }

    @Test func zebraBeatsTheFieldTint() async throws {
        let rig = try Rig()
        var tinted = frame()
        tinted.items[0].fieldValues = Array(repeating: 0.5, count: Self.sphere.positions.count)
        tinted.items[0].fieldRamp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)
        let withTint = try await rig.draw(tinted)
        let withoutTint = try await rig.draw(frame())
        #expect(withTint == withoutTint)
    }

    @Test func aSelectedFaceMixesTowardTheSelectionColour() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(frame())
        var selected = frame()
        selected.items[0].selectedFaces = [FaceID(0)]
        let marked = try await rig.draw(selected)
        let selection = ViewportPalette.dracula.selection
        let channels = [selection.x, selection.y, selection.z]
        var checked = 0
        for pixel in clearPixels(perspective: false).prefix(60) {
            let (a, b) = (Rig.color(plain, pixel.x, pixel.y), Rig.color(marked, pixel.x, pixel.y))
            let wanted = (0..<3).map { Double(a[$0]) * 0.45 + Double(channels[$0]) * 255 * 0.55 }
            if zip(b, wanted).allSatisfy({ abs(Double($0) - $1) <= 4 }) { checked += 1 }
        }
        #expect(checked >= 50, "\(checked) of 60 pixels mix 55% toward the selection colour")
    }
}
#endif
