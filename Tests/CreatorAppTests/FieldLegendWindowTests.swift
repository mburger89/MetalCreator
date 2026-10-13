import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The legend in the app's real window (fields spec §6): it appears with a sampled field, its buttons reach the model, and it
/// goes with the selection. How it looks is a human check (group FI).
@MainActor
struct FieldLegendWindowTests {
    /// A 20 × 10 × 10 box into an Output beside a Radial Gradient (radius 10).
    func open() async throws -> (AppWindow, Node) {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, ["width": .number(20)])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
        let output = builder.add(OutputNode.self)
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(10)])
        builder.wire(rectangle, "profile", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        return (try await AppWindow.open(builder.graph), radial)
    }

    func select(_ node: Node?, in app: AppWindow) async throws {
        app.model.editor.selection = node.map { [$0.id] } ?? []
        await app.model.settle()
        try await app.window.runUntilIdle()
    }

    /// The one control (not its text) the window labels `label`.
    func control(_ label: String, in app: AppWindow) throws -> TestElement {
        let found = try app.window.elements { $0.label == label && $0.role != .staticText }
        return try #require(found.count == 1 ? found.first : nil, "\(found.count) controls are labelled \(label)")
    }

    func controls(_ label: String, in app: AppWindow) throws -> Int {
        try app.window.elements { $0.label == label && $0.role != .staticText }.count
    }

    @Test func noLegendWithoutAFieldPreview() async throws {
        let (app, _) = try await open()
        #expect(app.model.fieldPreview.legend == nil)
        #expect(try controls("XZ", in: app) == 0 && controls("0…1", in: app) == 0)
    }

    @Test func aSelectedFieldNodeShowsTheLegendWithItsNumbersAndButtons() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        let legend = try #require(app.model.fieldPreview.legend)
        let labels = try #require(legend.labels)
        for text in [labels.low, labels.high] {
            #expect(try app.window.elements { $0.label == text || $0.value == text }.count >= 1, "the number \(text)")
        }
        for title in ["XY", "YZ", "XZ", "Off", "0…1"] {
            _ = try control(title, in: app)
        }
        #expect(try controls("Plane", in: app) == 0, "a radial gradient has no plane of its own")
        #expect(try control("XY", in: app).isSelected, "the slice starts on the axis plane nearest the camera")
    }

    @Test func thePicksReachTheModel() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        try app.window.click(try control("YZ", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.choice == .axis(.yz))
        try app.window.click(try control("Off", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.choice == .hidden && app.model.viewport.slice == nil)
        try app.window.click(try control("0…1", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.usesUnitRange && app.model.fieldPreview.legend?.labels?.mid == "0.5")
    }

    @Test func theLegendGoesWhenTheSelectionDoes() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        _ = try control("YZ", in: app)
        try await select(nil, in: app)
        #expect(try controls("YZ", in: app) == 0)
    }

    @Test func theCardStandsAboveTheTriadAndRightOfTheLeftDockedPanel() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self)
        let box = builder.box()
        _ = box
        let app = try await AppWindow.open(builder.graph, dock: .left)
        try await select(radial, in: app)
        let slice = try #require(try app.window.elements(role: .radioGroup).first { $0.label == "Slice" })
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: app.model.panelWidth, panelHeight: app.model.panelHeight)
        let (left, bottom) = (Double(slice.frame.origin.x.value), Double(slice.frame.origin.y.value + slice.frame.size.height.value))
        #expect(left >= insets.leading, "right of the panel: \(left) against \(insets.leading)")
        #expect(bottom <= app.size.y - insets.bottom, "above the triad: \(bottom) against \(app.size.y - insets.bottom)")
    }
}
