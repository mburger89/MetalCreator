import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The export sheet in the app's real window (implicit spec §5.3): it appears while a mesh exports, its Cancel stops the export, and it
/// goes when the export ends. How it looks is a human check (group IM).
@MainActor
struct ExportSheetWindowTests {
    /// A sphere of radius 10 meshed at 0.05 mm on export: long enough to cancel.
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(0.05)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return try await AppWindow.open(builder.graph)
    }

    func waitForRun(_ app: AppWindow) async throws -> ExportRun {
        var attempts = 0
        while app.model.exportRun == nil, attempts < 2000 {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }
        return try #require(app.model.exportRun)
    }

    func controls(_ label: String, in app: AppWindow) throws -> [TestElement] {
        try app.window.elements { $0.label == label && $0.role != .staticText }
    }

    @Test func noSheetWithoutAnExport() async throws {
        let app = try await open()
        #expect(try controls("Cancel", in: app).isEmpty)
        #expect(try app.window.elements { $0.label == "Exporting “Output”" || $0.value == "Exporting “Output”" }.isEmpty)
    }

    @Test func theSheetShowsTheExportAndItsCancelStopsIt() async throws {
        let app = try await open()
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).stl")
        let task = Task { try await app.model.export(.stl, to: url) }
        let run = try await waitForRun(app)
        try await app.window.runUntilIdle()
        let title = run.title
        #expect(try app.window.elements { $0.label == title || $0.value == title }.count >= 1)
        let cancel = try #require(try controls("Cancel", in: app).first)
        try app.window.click(cancel)
        #expect(run.isCancelling)
        try await task.value
        try await app.window.runUntilIdle()
        #expect(app.model.exportRun == nil && !FileManager.default.fileExists(atPath: url.path))
        #expect(try controls("Cancel", in: app).isEmpty, "the sheet goes with the export")
    }
}
