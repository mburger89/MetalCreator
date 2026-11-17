#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// A sheet (a face on an open shell, face flag bit 8) seen from behind is drawn in the theme's sheet-back colour, lit with the
/// flipped normal; seen from the front it is the usual shade. A closed solid's back faces (cut view) are unchanged.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct SheetBackRenderTests {
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func aSheetSeenFromBehindIsTheSheetBackColour() throws {
        let rig = try RendererCacheTests.Rig()
        let back = color(try rig.draw(SheetFixtures.sheetFrame(facingEye: false, openShell: true)), 100, 100)
        let expected = SheetFixtures.backExpected(.dracula, seenNormalZ: 1)
        for channel in 0..<3 { #expect(abs(back[channel] - expected[channel]) <= 3, "\(back) against \(expected)") }
    }

    @Test func aSheetSeenFromTheFrontIsTheUsualShadeAndAClosedBackFaceIsNot() throws {
        let rig = try RendererCacheTests.Rig()
        let front = color(try rig.draw(SheetFixtures.sheetFrame(facingEye: true, openShell: true)), 100, 100)
        let plainFront = color(try rig.draw(SheetFixtures.sheetFrame(facingEye: true, openShell: false)), 100, 100)
        #expect(front == plainFront, "the flag changes nothing on a front face")
        let back = color(try rig.draw(SheetFixtures.sheetFrame(facingEye: false, openShell: true)), 100, 100)
        #expect(front != back, "\(front) \(back)")
        let closedBack = color(try rig.draw(SheetFixtures.sheetFrame(facingEye: false, openShell: false)), 100, 100)
        #expect(closedBack != back, "without bit 8 a back face keeps its plain shade: \(closedBack) \(back)")
    }
}
#endif
