import CreatorGeometry
import CreatorKernel
import CreatorStyle
import Testing
@testable import CreatorViewport

/// The viewport's GPU colours come from its theme (spec §6.6): byte for byte Dracula by default, and a theme
/// switch reaches the uniforms and the cube's label ink on the next frame.
@MainActor
struct ViewportPaletteTests {
    static func rgba(_ rgb: UInt32, _ alpha: Float = 1) -> SIMD4<Float> {
        SIMD4(Float((rgb >> 16) & 0xff) / 255, Float((rgb >> 8) & 0xff) / 255, Float(rgb & 0xff) / 255, alpha)
    }

    @Test func theDefaultPaletteIsDraculaByteForByte() {
        let palette = ViewportPalette.dracula
        #expect(palette.backgroundTop == Self.rgba(0x3a3d4e) && palette.backgroundBottom == Self.rgba(0x191a21))
        #expect(palette.shadeLight == Self.rgba(0xc5c8de) && palette.shadeDark == Self.rgba(0x6f739a))
        #expect(palette.edge == Self.rgba(0xf8f8f2, 0.9))
        #expect(palette.hover == Self.rgba(0x8be9fd) && palette.selection == Self.rgba(0xff79c6))
        #expect(palette.solid == Self.rgba(0xbd93f9) && palette.feature == Self.rgba(0xffb86c))
        #expect(palette.gridMinor == Self.rgba(0x44475a) && palette.gridMajor == Self.rgba(0x6272a4))
        #expect(palette.cubeFace == Self.rgba(0x44475a) && palette.cubeRim == Self.rgba(0x343746))
        #expect(palette.cubeLabel == Self.rgba(0xf8f8f2))
        #expect(palette.axisX == Self.rgba(0xff5555) && palette.axisY == Self.rgba(0x50fa7b) && palette.axisZ == Self.rgba(0x8be9fd))
    }

    @Test func aThemesRolesBecomeItsGPUColours() {
        let palette = ViewportPalette(.alucard)
        #expect(palette.hover == Self.rgba(0x036a96), "hover is the theme's focus colour")
        #expect(palette.selection == Self.rgba(0xa3144d))
        #expect(palette.solid == Self.rgba(0x644ac9) && palette.feature == Self.rgba(0xa34d14), "handles in header colours")
        #expect(palette.cubeLabel == Self.rgba(0x1f1f1f))
        #expect(palette.backgroundTop == Self.rgba(0xfffbeb))
    }

    @Test func aThemeSwitchIsDrawnOnTheNextFrame() {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(model.frame(at: 0).palette == .dracula)
        let before = model.renderKey
        model.theme = .alucard
        #expect(model.renderKey != before, "the on-demand surface redraws")
        let frame = model.frame(at: 0)
        #expect(frame.palette == ViewportPalette(.alucard))
        #expect(frame.palette.cubeLabel == Self.rgba(0x1f1f1f), "the cube's label ink")
        #expect(GPUGeometry.gridUniforms(frame).minorColor == Self.rgba(0xcfcfde))
        #expect(ShadeUniforms(frame.palette).hover == Self.rgba(0x036a96))
        let cube = GPUGeometry.cubeVertices(hovered: .right, pose: frame.pose, palette: frame.palette)
        let right = (ViewCubeCell.all.firstIndex { $0.region == .right } ?? 0) * 6
        #expect(cube[right].color == Self.rgba(0x036a96), "the hovered cube region in the theme's focus colour")
        #expect(model.labelColor == ColorTheme.alucard.colors.foreground.color)
        #expect(model.hintColor == ColorTheme.alucard.colors.comment.color)
    }
}
