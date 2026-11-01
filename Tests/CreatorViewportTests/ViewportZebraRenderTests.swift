#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Foundation
import Metal
import Testing
@testable import CreatorViewport

/// Zebra stripes in the Metal renderer. A sphere of radius 10 about the origin is seen in a 200-point view (400 pixels, scale 2).
/// Orthographic, the front pose of `OffscreenRenderTests` puts it at 5 points per mm centred on (100, 100); the view axes are
/// x = right, y = up, z = toward the eye, and each test asks `ZebraBand.value` (the CPU twin) what a pixel should be.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ViewportZebraRenderTests {
    static let radius = 10.0
    static let sphere = TestMeshes.sphere(radius: radius, segments: 96)
    static let bounds = BoundingBox(min: Vector3(-10, -10, -10), max: Vector3(10, 10, 10))
    static let perspective = CameraPose(target: .zero, distance: 60, yaw: 0, pitch: 0, projection: .perspective)
    static let horizontal = ViewportZebra(direction: .horizontal, stripes: 12, blackShare: 0.5)
    static let fine = ViewportZebra(direction: .horizontal, stripes: 40, blackShare: 0.5)

    func frame(pose: CameraPose = orthographic, zebra: ViewportZebra? = horizontal, ghost: Bool = false,
               clip: ViewportClip? = nil) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: Self.sphere, pose: pose, size: OffscreenRenderTests.size, bounds: Self.bounds)
        frame.items[0].isGhost = ghost
        frame.zebra = zebra
        frame.showsViewCube = false
        frame.clip = clip
        return frame
    }

    static let orthographic = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                                         projection: .orthographic)

    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    /// The pixel's brightness against the midpoint of the white band's darkest (0.8 of light) and the black band's lightest.
    func isWhite(_ colour: [Int]) -> Bool {
        let palette = ViewportPalette.dracula
        let white = Double(palette.shadeLight.x) * 255 * 0.8
        let black = Double(palette.shadeDark.x) * 255 * 0.15
        return Double(colour[0]) > (white + black) / 2
    }

    /// What the twin says for the sphere under the pixel (x, y) in points, and how far from a band edge it lies (in periods).
    struct Expectation { var white: Bool; var margin: Double }

    /// The sphere's view-space normal and the unit vector to the eye at a pixel, or nil off the sphere.
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
        let margin = min(abs(fraction - zebra.blackShare), fraction, 1 - fraction)
        return Expectation(white: white, margin: margin)
    }

    /// Changes between white and black along a line of pixels.
    func changes(_ pixels: [UInt8], from: (Int, Int), to: (Int, Int), steps: Int) -> Int {
        var count = 0
        var last: Bool?
        for step in 0...steps {
            let x = from.0 + (to.0 - from.0) * step / steps, y = from.1 + (to.1 - from.1) * step / steps
            let white = isWhite(color(pixels, x, y))
            if let last, last != white { count += 1 }
            last = white
        }
        return count
    }

    /// Pixels of the sphere (not near its rim) whose expectation is clear of any band edge.
    func clearPixels(perspective: Bool, zebra: ViewportZebra = horizontal) -> [(x: Int, y: Int, white: Bool)] {
        var found: [(x: Int, y: Int, white: Bool)] = []
        for y in stride(from: 56, to: 144, by: 3) {
            for x in stride(from: 56, to: 144, by: 3) {
                guard let sample = sphereSample(Double(x), Double(y), perspective: perspective) else { continue }
                let e = expectation(sample, zebra: zebra)
                if e.margin > 0.1 { found.append((x, y, e.white)) }
            }
        }
        return found
    }

    @Test func aSphereIsStriped() throws {
        let rig = try RendererCacheTests.Rig()
        let pixels = try rig.draw(frame())
        #expect(changes(pixels, from: (100, 56), to: (100, 144), steps: 88) >= 6)
        let clear = clearPixels(perspective: false)
        #expect(clear.count > 100)
        var wrong = 0
        for pixel in clear where isWhite(color(pixels, pixel.x, pixel.y)) != pixel.white { wrong += 1 }
        #expect(wrong * 50 < clear.count, "\(wrong) of \(clear.count) pixels disagree with the twin")
        for pixel in [clear[clear.count / 4], clear[clear.count / 2], clear[3 * clear.count / 4]] {
            #expect(isWhite(color(pixels, pixel.x, pixel.y)) == pixel.white)
        }
    }

    @Test func verticalStripesRunTheOtherWay() throws {
        let rig = try RendererCacheTests.Rig()
        let vertical = ViewportZebra(direction: .vertical, stripes: 12, blackShare: 0.5)
        let pixels = try rig.draw(frame(zebra: vertical))
        let row = changes(pixels, from: (56, 100), to: (144, 100), steps: 88)
        let column = changes(pixels, from: (100, 56), to: (100, 144), steps: 88)
        #expect(row >= 6)
        #expect(column < row)
        let clear = clearPixels(perspective: false, zebra: vertical)
        let wrong = clear.filter { isWhite(color(pixels, $0.x, $0.y)) != $0.white }.count
        #expect(wrong * 50 < clear.count)
    }

    @Test func perspectiveStripesUseThePixelsViewVector() throws {
        let rig = try RendererCacheTests.Rig()
        let persp = try rig.draw(frame(pose: Self.perspective, zebra: Self.fine))
        let ortho = try rig.draw(frame(pose: Self.orthographic, zebra: Self.fine))
        // Pixels where the two views' expectations clearly differ.
        var differing: [(x: Int, y: Int, white: Bool)] = []
        for y in stride(from: 70, to: 130, by: 2) {
            for x in stride(from: 70, to: 130, by: 2) {
                guard let p = sphereSample(Double(x), Double(y), perspective: true),
                      let o = sphereSample(Double(x), Double(y), perspective: false) else { continue }
                let (ep, eo) = (expectation(p, zebra: Self.fine), expectation(o, zebra: Self.fine))
                if ep.margin > 0.1, eo.margin > 0.1, ep.white != eo.white { differing.append((x, y, ep.white)) }
            }
        }
        #expect(differing.count >= 3)
        for pixel in differing.prefix(5) {
            #expect(isWhite(color(persp, pixel.x, pixel.y)) == pixel.white, "perspective pixel \(pixel.x),\(pixel.y)")
            #expect(isWhite(color(persp, pixel.x, pixel.y)) != isWhite(color(ortho, pixel.x, pixel.y)))
        }
        // Forty stripes are narrow towards the rim, where interpolated normals and antialiasing blur them: judge the middle.
        let clear = clearPixels(perspective: true, zebra: Self.fine).filter { abs($0.x - 100) < 30 && abs($0.y - 100) < 30 }
        let wrong = clear.filter { isWhite(color(persp, $0.x, $0.y)) != $0.white }.count
        #expect(clear.count > 50)
        #expect(wrong * 20 < clear.count, "\(wrong) of \(clear.count)")
    }

    /// The pixel in points where a world point lands in an orthographic view of `pose` (5 points per mm).
    func project(_ point: Vector3, _ pose: CameraPose) -> (x: Int, y: Int) {
        (Int((100 + 5 * point.dot(pose.right)).rounded()), Int((100 - 5 * point.dot(pose.up)).rounded()))
    }

    @Test func aLockedZebraStaysPutWhenOrbiting() throws {
        let rig = try RendererCacheTests.Rig()
        let poseA = Self.orthographic
        var poseB = Self.orthographic
        poseB.yaw = 0.7
        poseB.pitch = 0.3
        let lock = ViewportZebra.Frame(right: poseA.right, up: poseA.up, toEye: poseA.toEye)
        let locked = ViewportZebra(direction: .horizontal, stripes: 12, blackShare: 0.5, lock: lock)
        let lockedB = try rig.draw(frame(pose: poseB, zebra: locked))
        let unlockedB = try rig.draw(frame(pose: poseB))
        // Surface points visible from both poses, whose locked band is clear of an edge.
        var checked = 0
        var unlockedDiffers = 0
        for i in 0..<40 {
            let azimuth = -0.5 + 0.05 * Double(i), polar = 1.7 + 0.02 * Double(i % 7)
            let normal = Vector3(sin(polar) * sin(azimuth), -sin(polar) * cos(azimuth), cos(polar))
            guard normal.dot(poseB.toEye) > 0.4, normal.dot(poseA.toEye) > 0.4 else { continue }
            let expected = expectation((normal: Vector3(normal.dot(lock.right), normal.dot(lock.up), normal.dot(lock.toEye)),
                                        toEye: Vector3(0, 0, 1)), zebra: locked)
            guard expected.margin > 0.1 else { continue }
            let pixel = project(normal * Self.radius, poseB)
            #expect(isWhite(color(lockedB, pixel.x, pixel.y)) == expected.white, "point \(i) at \(pixel)")
            if isWhite(color(unlockedB, pixel.x, pixel.y)) != expected.white { unlockedDiffers += 1 }
            checked += 1
        }
        #expect(checked >= 8)
        #expect(unlockedDiffers >= 1, "unlocked, orbiting moves the stripes")
    }

    @Test func ghostsAreNotStriped() throws {
        let rig = try RendererCacheTests.Rig()
        let striped = try rig.draw(frame(ghost: true))
        let plain = try rig.draw(frame(zebra: nil, ghost: true))
        #expect(striped == plain)
    }

    @Test func theClipStillCutsAStripedPart() throws {
        let rig = try RendererCacheTests.Rig()
        let clip = ViewportClip(origin: .zero, normal: Vector3(0, -1, 0))
        let background = try rig.draw(frame(zebra: nil, clip: clip))
        let whole = try rig.draw(frame())
        let cut = try rig.draw(frame(clip: clip))
        // The near half is gone: pixels of the sphere's front, now showing the far wall (striped, with the flipped normal).
        #expect(cut != whole)
        let palette = ViewportPalette.dracula
        let fallback = (0..<3).map { channel -> Int in
            let light = [palette.shadeLight.x, palette.shadeLight.y, palette.shadeLight.z][channel]
            let dark = [palette.shadeDark.x, palette.shadeDark.y, palette.shadeDark.z][channel]
            return Int(((light + dark) / 2 * 0.55 * 255).rounded())
        }
        _ = background
        var checked = 0, wrong = 0, fallbackLike = 0
        for y in stride(from: 56, to: 146, by: 3) {
            for x in stride(from: 56, to: 146, by: 3) {
                guard let sample = sphereSample(Double(x), Double(y), perspective: false) else { continue }
                // The far wall's flipped outward normal, in view space.
                let flipped = Vector3(-sample.normal.x, -sample.normal.y, sample.normal.z)
                let e = expectation((normal: flipped, toEye: sample.toEye))
                guard e.margin > 0.1 else { continue }
                let c = color(cut, x, y)
                if isWhite(c) != e.white { wrong += 1 }
                if zip(c, fallback).allSatisfy({ abs($0 - $1) <= 6 }) { fallbackLike += 1 }
                checked += 1
            }
        }
        #expect(checked > 100)
        // A few antialiased band edges land on the other side of the threshold.
        #expect(wrong * 25 < checked, "\(wrong) of \(checked) back-face pixels disagree with the twin")
        #expect(fallbackLike * 25 < checked, "\(fallbackLike) pixels are the darkened fallback")
    }

    @Test func zebraBeatsTheFieldTint() throws {
        let rig = try RendererCacheTests.Rig()
        var tinted = frame()
        tinted.items[0].fieldValues = Array(repeating: 0.5, count: Self.sphere.positions.count)
        tinted.items[0].fieldRamp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)
        let withTint = try rig.draw(tinted)
        let withoutTint = try rig.draw(frame())
        #expect(withTint == withoutTint)
        var tintOnly = tinted
        tintOnly.zebra = nil
        #expect(try rig.draw(tintOnly) != withTint, "the tint draws when there is no zebra")
    }

    @Test func noZebraDrawsAsBefore() throws {
        let rig = try RendererCacheTests.Rig()
        let before = try rig.draw(frame(zebra: nil))
        _ = try rig.draw(frame())
        let after = try rig.draw(frame(zebra: nil))
        #expect(before == after)
        // The plain shading of the sphere's centre, where the normal faces the eye: mix(dark, light, 0.15 + 0.75 * diffuse).
        let palette = ViewportPalette.dracula
        let key = Vector3(-0.4, 0.7, 0.6)
        let diffuse = max(0, min(1, key.z / key.length))
        let t = Float(0.15 + 0.75 * diffuse)
        let centre = color(before, 100, 100)
        let wanted = [palette.shadeLight.x, palette.shadeLight.y, palette.shadeLight.z].enumerated().map { index, light in
            let dark = [palette.shadeDark.x, palette.shadeDark.y, palette.shadeDark.z][index]
            return Int(((dark + (light - dark) * t) * 255).rounded())
        }
        #expect(zip(centre, wanted).allSatisfy { abs($0 - $1) <= 3 }, "\(centre) against \(wanted)")
    }
}
#endif
