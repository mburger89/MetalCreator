import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The host's entries in the context menu: a dimension's from its editor, a tool's from the tool.
@MainActor
struct DimensionMenuTests {
    let id = OverlayDimensionID("a")
    let pin = HostMenuAction(title: "Pin", key: "pin")

    func makeModel() -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        return model
    }

    @Test func aDimensionsMenuComesFromItsEditor() throws {
        let model = makeModel()
        let editor = FakeDimensionEditor()
        editor.menus[id] = [pin]
        model.dimensionEditor = editor
        let tool = RecordingTool()
        tool.navigation = .planar
        model.tool = tool
        model.showDimensions([sixtyMillimetres()])
        let placed = try #require(model.placedDimensions(measuring: .eightPerCharacter).first)
        let centre = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        let items = model.contextMenuItems(at: centre)
        #expect(items == [.host(pin, dimension: id)])
        #expect(items.map(\.title) == ["Pin"])
        model.choose(items[0])
        #expect(editor.performed == [FakeDimensionEditor.Performed(action: pin, id: id)])
        #expect(tool.performedMenuActions.isEmpty)
    }

    @Test func aToolCanOfferAMenuOffTheModel() {
        let model = makeModel()
        let tool = RecordingTool()
        let action = HostMenuAction(title: "A", key: "a")
        tool.menu = [action]
        model.tool = tool
        let point = ScreenPoint(50, 250)
        let items = model.contextMenuItems(at: point)
        #expect(items == [.host(action, dimension: nil)])
        model.choose(items[0])
        #expect(tool.performedMenuActions == [action])
        #expect(tool.menuPoints == [point])
        #expect(model.contextMenuItems(at: nil).isEmpty)
    }
}
