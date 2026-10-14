import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The "Preview 0.4 mm" badge in the app's real window (implicit spec §5.1). How it looks is a human check (group IM).
@MainActor
struct MeshBadgeWindowTests {
    func open(preview: Double) async throws -> AppWindow {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = builder.add(MeshNode.self, ["preview resolution": .number(preview)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return try await AppWindow.open(builder.graph)
    }

    func texts(_ text: String, in app: AppWindow) throws -> Int {
        try app.window.elements { $0.label == text || $0.value == text }.count
    }

    @Test func aMeshPreviewShowsItsBadge() async throws {
        let app = try await open(preview: 1)
        try await app.window.runUntilIdle()
        #expect(app.model.meshRefinement.badge == .init(text: "Preview 1 mm", isRefining: false))
        #expect(try texts("Preview 1 mm", in: app) >= 1)
    }

    @Test func theBadgeFollowsTheRefinementAndKeepsItsLastResolution() async throws {
        let app = try await open(preview: 0.06)
        await app.model.meshRefinement.waitForRefinement()
        await app.model.settle()
        try await app.window.runUntilIdle()
        #expect(try texts("Preview 0.06 mm", in: app) >= 1)
        #expect(try texts("Preview 0.094 mm", in: app) == 0)
    }

    @Test func noMeshNoBadge() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph)
        #expect(app.model.meshRefinement.badge == nil)
        #expect(try app.window.elements { ($0.label ?? "").hasPrefix("Preview ") }.isEmpty)
    }
}
