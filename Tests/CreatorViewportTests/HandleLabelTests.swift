import CreatorGeometry
import Foundation
import MetalUI
import Testing
@testable import CreatorViewport

/// A handle's value beside its knob (spec §6.5) is boxed to its measured text (gap S5-c, MetalUI C23), not to a fixed 96
/// points, so a long value is neither clipped nor given more room than it needs.
@MainActor
struct HandleLabelTests {
    let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                           projection: .orthographic)

    func makeModel(value: Double, style: HandleStyle = .radial) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: front, clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.showHandles([
            ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: value, range: 0...1e9, style: style, tint: .feature),
        ])
        return model
    }

    @Test func theBoxIsTheMeasuredWidthAndOneLineTall() throws {
        let label = try #require(makeModel(value: 3).handleLabels(measuring: .fake).first)
        #expect(label.text == "R 3 mm")
        #expect(label.size == ViewportSize(width: 6 * 6, height: HandleLabel.height), "the fake measure is 6 points a character")
        #expect(label.origin == ScreenPoint(label.position.x, label.position.y - HandleLabel.height / 2))
    }

    @Test func aLongValueGetsAWiderBoxThanAShortOne() throws {
        let short = try #require(makeModel(value: 3, style: .linear).handleLabels(measuring: .fake).first)
        let long = try #require(makeModel(value: 123_456_789.12, style: .linear).handleLabels(measuring: .fake).first)
        #expect(long.size.width > short.size.width)
        #expect(long.text.hasSuffix(" mm"))
    }

    #if canImport(Metal)
    /// The real measure: every glyph of a long value lies inside the box the view gives it.
    @Test(arguments: [3.0, 12.5, 9.99])
    func theViewDrawsTheValueInsideItsBox(_ value: Double) throws {
        let model = makeModel(value: value)
        model.viewSize = ViewportSize(width: 1400, height: 900)
        let label = try #require(model.handleLabels(measuring: .real()).first)
        let scene = renderFrame({ ZStack { ViewportView(model: model) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let inside = scene.glyphs.filter { glyph in
            let x0 = Double(glyph.bounds.origin.x) / 2, x1 = Double(glyph.bounds.origin.x + glyph.bounds.size.width) / 2
            let y0 = Double(glyph.bounds.origin.y) / 2, y1 = Double(glyph.bounds.origin.y + glyph.bounds.size.height) / 2
            return x0 >= label.origin.x - 0.5 && x1 <= label.origin.x + label.size.width + 0.5
                && y0 >= label.origin.y && y1 <= label.origin.y + label.size.height
        }
        #expect(inside.count == label.text.filter { !$0.isWhitespace }.count, "every glyph of \(label.text)")
    }
    #endif
}
