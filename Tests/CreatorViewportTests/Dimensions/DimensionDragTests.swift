import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
import Testing
@testable import CreatorViewport

/// A primary drag pressed on a drawn dimension's text is offered to the tool before an ordinary drag (DIM-2: dragging a label).
@MainActor
struct DimensionDragTests {
    let id = OverlayDimensionID("a")
    let measure = TextMeasure.eightPerCharacter

    /// A model with the 60 mm dimension drawn and a tool set; returns the middle of the text and a point on the line off it.
    func setUp() throws -> (ViewportModel, RecordingTool, text: ScreenPoint, line: ScreenPoint) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        let tool = RecordingTool()
        model.tool = tool
        model.showDimensions([sixtyMillimetres()])
        let placed = try #require(model.placedDimensions(measuring: measure).first)
        let text = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        let line = ScreenPoint(placed.textOrigin.x - 3 * placed.textSize.width, text.y)
        #expect(model.dimension(at: line) == nil)
        return (model, tool, text, line)
    }

    @Test func aDragOnATextIsOfferedToTheToolFirst() throws {
        let (model, tool, text, _) = try setUp()
        tool.claimsDimension = true
        let pose = model.pose
        model.pointerDown(at: text, modifiers: [])
        model.pointerDragged(to: ScreenPoint(text.x + 10, text.y + 5))
        model.pointerUp(at: ScreenPoint(text.x + 10, text.y + 5))
        #expect(tool.dimensionDrags == [id])
        #expect(!tool.calls.contains { $0.hasPrefix("began ") }, "dragBegan(at:) is not offered")
        #expect(tool.calls.contains { $0.hasPrefix("dragged") } && tool.calls.contains { $0.hasPrefix("ended") })
        #expect(model.pose == pose)
    }

    @Test func aDeclinedTextDragFallsThrough() throws {
        let (model, tool, text, _) = try setUp()
        tool.claimsDimension = false
        tool.claims = true
        model.pointerDown(at: text, modifiers: [])
        #expect(tool.dimensionDrags == [id])
        #expect(tool.calls.contains { $0.hasPrefix("began ") })
        model.pointerUp(at: text)
    }

    @Test func aDragOffTheTextIsNotOffered() throws {
        let (model, tool, _, line) = try setUp()
        tool.claimsDimension = true
        model.pointerDown(at: line, modifiers: [])
        model.pointerUp(at: line)
        #expect(tool.dimensionDrags.isEmpty)
    }
}
