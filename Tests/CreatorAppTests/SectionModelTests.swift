import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp

/// The section view in the app (section spec §3, §5): settings on the document, a clip and a handle on the viewport.
@MainActor
struct SectionModelTests {
    func boxApp() async -> (AppModel, Graph) {
        var builder = GraphBuilder()
        _ = builder.box()
        return (await makeApp(builder.graph), builder.graph)
    }

    @Test func theAppSectionsTheViewportAndShowsTheHandle() async {
        let (app, _) = await boxApp()
        #expect(app.viewport.clip == nil && !app.viewport.handles.contains { $0.id == SectionModel.handleID })
        app.setSection(true)
        await app.settle()
        #expect(app.document.section?.isOn == true && app.viewport.clip != nil)
        #expect(app.viewport.handles.contains { $0.id == SectionModel.handleID })
        app.handleChanged(SectionModel.handleID, 2, .ended)
        #expect(app.document.section?.offset == 2 && !app.document.canUndo && !app.isEdited)
    }

    @Test func offIsRememberedAndComesBack() async {
        let (app, _) = await boxApp()
        app.setSection(true)
        await app.settle()
        app.setSectionOffset(3)
        await app.settle()
        app.flipSection()
        await app.settle()
        let flipped = app.document.section?.isFlipped
        app.setSection(false)
        await app.settle()
        #expect(app.viewport.clip == nil && !app.viewport.handles.contains { $0.id == SectionModel.handleID })
        #expect(app.document.section?.isOn == false && app.document.section?.offset == 3)
        app.setSection(true)
        await app.settle()
        #expect(app.document.section?.offset == 3 && app.document.section?.isFlipped == flipped && app.viewport.clip != nil)
    }

    @Test func typedOffsets() async {
        let (app, _) = await boxApp()
        app.setSection(true)
        await app.settle()
        #expect(app.commitSectionOffset(text: "12.5") && app.document.section?.offset == 12.5)
        #expect(app.commitSectionOffset(text: "1 in") && app.document.section?.offset == 25.4)
        for bad in ["abc", "", "1e999"] {
            #expect(!app.commitSectionOffset(text: bad) && app.document.section?.offset == 25.4)
        }
        app.setSectionOffset(.nan)
        #expect(app.document.section?.offset == 25.4)
    }

    @Test func aSavedSectionComesBackAndNewStartsWithout() async throws {
        let (app, graph) = await boxApp()
        app.setSection(true)
        await app.settle()
        app.setSectionOffset(4)
        await app.settle()
        let file = try GraphFileIO.decode(try app.document.fileData(), registry: app.registry)
        app.load(GraphFile(graph: graph), from: nil)
        await app.settle()
        #expect(app.document.section == nil && app.viewport.clip == nil)
        app.load(file, from: nil)
        await app.settle()
        #expect(app.document.section?.offset == 4)
        #expect(app.viewport.clip != nil)
    }

    @Test func anEmptyDocumentStaysUncut() async {
        let app = await makeApp()
        app.setSection(true)
        await app.settle()
        #expect(app.document.section == nil && app.viewport.clip == nil)
    }

    @Test func sketchModeHidesTheSection() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        app.setSection(true)
        await app.settle()
        #expect(app.viewport.clip != nil)
        app.beginSketch(for: sketch.id)
        await app.settle()
        #expect(app.sketch != nil && app.viewport.clip == nil)
        #expect(!app.viewport.handles.contains { $0.id == SectionModel.handleID })
        app.sketch?.stop()
        app.sketch = nil
        await app.settle()
        #expect(app.viewport.clip != nil)
    }

    @Test func switchingToAnOriginPlane() async throws {
        let (app, _) = await boxApp()
        let face = try #require(app.viewport.items.first?.solid.topology.faces.first)
        app.document.section = SectionSettings(isOn: true, reference: .face(FacePick(tags: face.tags)), offset: 1, isFlipped: false)
        app.setSectionOrigin(.yz)
        await app.settle()
        let centre = try #require(app.viewport.sceneBounds?.center)
        #expect(app.document.section?.reference == .origin(.yz) && app.document.section?.offset == centre.x)
    }

    @Test func tappingTheSelectedOriginPlaneKeepsTheTypedOffset() async {
        let (app, _) = await boxApp()
        app.setSection(true)
        await app.settle()
        guard case .origin(let origin)? = app.document.section?.reference else {
            Issue.record("expected an origin plane")
            return
        }
        app.setSectionOffset(7)
        app.setSectionOrigin(origin)
        #expect(app.document.section?.offset == 7)
    }

    @Test func switchingFromAFaceCutsTheViewersSide() async throws {
        let (app, _) = await boxApp()
        let face = try #require(app.viewport.items.first?.solid.topology.faces.first)
        for flipped in [false, true] {
            app.document.section = SectionSettings(isOn: true, reference: .face(FacePick(tags: face.tags)), offset: 1, isFlipped: flipped)
            app.setSectionOrigin(.xy)
            let bounds = try #require(app.viewport.sceneBounds)
            let expected = SectionGeometry.starting(origin: .xy, bounds: bounds, toEye: app.viewport.pose.toEye)
            #expect(app.document.section?.isFlipped == expected.isFlipped)
        }
    }
}
