#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Foundation
import Metal
import Testing
@testable import CreatorViewport

/// More zebra pixel tests: odd counts, a flat face, and the flag mixes (helpers are in `ViewportZebraRenderTests`).
extension ViewportZebraRenderTests {
    @Test func oddStripeCountsMatchTheTwin() throws {
        let rig = try RendererCacheTests.Rig()
        let odd = ViewportZebra(direction: .horizontal, stripes: 13, blackShare: 0.5)
        for (pose, isPerspective) in [(Self.orthographic, false), (Self.perspective, true)] {
            let pixels = try rig.draw(frame(pose: pose, zebra: odd))
            let clear = clearPixels(perspective: isPerspective, zebra: odd).filter { abs($0.x - 100) < 35 && abs($0.y - 100) < 35 }
            let wrong = clear.filter { isWhite(color(pixels, $0.x, $0.y)) != $0.white }.count
            #expect(clear.count > 100)
            #expect(wrong * 20 < clear.count, "perspective \(isPerspective): \(wrong) of \(clear.count)")
        }
    }

    @Test func aFlatFaceIsOneUniformBand() throws {
        let rig = try RendererCacheTests.Rig()
        let box = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))
        let target = Vector3(0, 0, 15)
        var found = false
        for pitch in [0.1, 0.2, 0.3, 0.4] {
            var pose = OffscreenRenderTests.front
            pose.pitch = pitch
            // The front face's normal (0, -1, 0) in view space; the twin's verdict for the whole face.
            let normal = Vector3(0, -1, 0)
            let view = Vector3(normal.dot(pose.right), normal.dot(pose.up), normal.dot(pose.toEye))
            let sample = (normal: view, toEye: Vector3(0, 0, 1))
            let expected = expectation(sample)
            guard expected.margin > 0.15 else { continue }
            found = true
            var frame = TestFrames.frame(mesh: TestMeshes.box(box), pose: pose, size: OffscreenRenderTests.size, bounds: box)
            frame.zebra = Self.horizontal
            frame.showsViewCube = false
            let pixels = try rig.draw(frame)
            var colours: [[Int]] = []
            for z in stride(from: 6.0, through: 24.0, by: 3.0) {
                for x in stride(from: -3.0, through: 3.0, by: 2.0) {
                    let point = Vector3(x, -10, z) - target
                    let spot = (x: Int((100 + 5 * point.dot(pose.right)).rounded()), y: Int((100 - 5 * point.dot(pose.up)).rounded()))
                    colours.append(color(pixels, spot.x, spot.y))
                }
            }
            let first = colours[0]
            for c in colours {
                #expect(zip(c, first).allSatisfy { abs($0 - $1) <= 3 }, "uniform: \(c) against \(first)")
                #expect(isWhite(c) == expected.white)
                #expect(c.allSatisfy { (0...255).contains($0) })
            }
            #expect(isWhite(first) == (ZebraBand.value(normal: view, toEye: Vector3(0, 0, 1), right: Vector3(1, 0, 0),
                                                       up: Vector3(0, 1, 0), back: Vector3(0, 0, 1), zebra: Self.horizontal) > 0.5))
            break
        }
        #expect(found, "a pitch with a clear band")
    }

    @Test func aSelectedFaceMixesTowardTheSelectionColour() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame())
        var selected = frame()
        selected.items[0].selectedFaces = [FaceID(0)]
        let marked = try rig.draw(selected)
        let selection = ViewportPalette.dracula.selection
        let channels = [selection.x, selection.y, selection.z]
        var checked = 0
        for pixel in clearPixels(perspective: false).prefix(60) {
            let (a, b) = (color(plain, pixel.x, pixel.y), color(marked, pixel.x, pixel.y))
            let wanted = (0..<3).map { Double(a[$0]) * 0.45 + Double(channels[$0]) * 255 * 0.55 }
            guard zip(b, wanted).allSatisfy({ abs(Double($0) - $1) <= 4 }) else { continue }
            checked += 1
        }
        #expect(checked >= 50, "\(checked) of 60 pixels mix 55% toward the selection colour")
    }
}
#endif
