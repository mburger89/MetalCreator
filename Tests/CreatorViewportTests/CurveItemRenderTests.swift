#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// A curve item draws its edges in the reference-dimension colour in every display mode, and writes nothing to the ID pass.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct CurveItemRenderTests {
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test(arguments: ShadingMode.allCases)
    func aCurvesPixelsAreTheReferenceColour(_ shading: ShadingMode) throws {
        let rig = try RendererCacheTests.Rig()
        let seen = color(try rig.draw(SheetFixtures.curveFrame(shading: shading)), 100, 100)
        let reference = ViewportPalette.dracula.dimensionReference
        let expected = [reference.x, reference.y, reference.z].map { Int(($0 * 255).rounded()) }
        for channel in 0..<3 { #expect(abs(seen[channel] - expected[channel]) <= 3, "\(shading): \(seen) against \(expected)") }
    }

    @Test func theIDPassReadsEmptyWhereACurveIs() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        #expect(picker.pick(at: ScreenPoint(100, 100), in: SheetFixtures.curveFrame()) == nil)
    }
}
#endif
