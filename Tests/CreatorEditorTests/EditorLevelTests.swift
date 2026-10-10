import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Entering a group, the breadcrumbs, and editing inside it (groups spec §6).
@MainActor
struct EditorLevelTests {
    @Test func enteringAGroupShowsItsInsideAndClearsTheSelection() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        #expect(editor.enterGroup(grouped.group))
        #expect(editor.levelPath == [grouped.group] && editor.isInsideGroup)
        #expect(editor.graphPath == .definition(grouped.definition.id))
        #expect(editor.selection.isEmpty, "the selection clears on changing level")
        #expect(Set(editor.graph.nodes.keys) == Set(grouped.definition.graph.nodes.keys))
        #expect(editor.rootGraph.nodes.count == 3, "the top level is as it was")
        #expect(editor.document.inspectedLevel == [grouped.group], "the document evaluates what the panel shows")
        #expect(editor.breadcrumbs == [Breadcrumb(title: "Graph", depth: 0), Breadcrumb(title: "Group", depth: 1)])
    }

    @Test func leavingAGroupGoesBackOutAndClearsTheSelectionAgain() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(!editor.exitGroup(), "nothing to leave on the top level, so the key goes on")
        #expect(editor.enterGroup(grouped.group))
        editor.selectAll()
        #expect(editor.exitGroup())
        #expect(editor.levelPath.isEmpty && editor.graphPath == .root && editor.selection.isEmpty)
        #expect(editor.graph.nodes.count == 3 && editor.document.inspectedLevel.isEmpty)
        #expect(editor.breadcrumbs == [Breadcrumb(title: "Graph", depth: 0)])
    }

    @Test func onlyAGroupNodeCanBeEntered() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(!editor.enterGroup(grouped.number.id))
        #expect(!editor.enterGroup(NodeID()))
        #expect(!editor.enterGroup(grouped.rectangle.id), "it is inside the group, not on the top level")
        #expect(editor.levelPath.isEmpty)
    }

    @Test func aLockedLevelCantBeEnteredOrLeft() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.isLevelLocked = true
        #expect(!editor.enterGroup(grouped.group) && editor.levelPath.isEmpty, "sketch mode holds the top level")
        editor.isLevelLocked = false
        #expect(editor.enterGroup(grouped.group))
        editor.isLevelLocked = true
        #expect(!editor.exitGroup() && editor.levelPath == [grouped.group])
        editor.goToLevel(0)
        #expect(editor.levelPath == [grouped.group], "a breadcrumb does nothing either")
        editor.isLevelLocked = false
        editor.goToLevel(0)
        #expect(editor.levelPath.isEmpty)
    }

    @Test func breadcrumbsGoBackToAnyLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        #expect(editor.enterGroup(inner))
        #expect(editor.levelPath == [grouped.group, inner])
        #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group", "Group 2"])
        editor.goToLevel(1)
        #expect(editor.levelPath == [grouped.group] && editor.selection.isEmpty)
        editor.enterGroup(inner)
        editor.goToLevel(0)
        #expect(editor.levelPath.isEmpty)
        editor.goToLevel(0)
        editor.goToLevel(3)
        #expect(editor.levelPath.isEmpty, "the level shown, or a deeper one, does nothing")
    }

    @Test func eachLevelRemembersItsPanAndZoom() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let top = CanvasTransform(offset: Vector2(50, 60), zoom: 2)
        editor.transform = top
        editor.enterGroup(grouped.group)
        #expect(editor.transform != top)
        #expect(editor.document.viewState.canvasZoom == 2, "the top level's is still the saved one")
        let inside = CanvasTransform(offset: Vector2(7, 8), zoom: 1.5)
        editor.transform = inside
        editor.exitGroup()
        #expect(editor.transform == top)
        editor.enterGroup(grouped.group)
        #expect(editor.transform == inside)
        #expect(editor.document.viewState.canvasOffset == Vector2(50, 60), "the inside's pan never reached the file")
    }

    @Test func aLevelEnteredForTheFirstTimeFramesItsNodes() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let visible = CanvasRect(corner: editor.transform.toCanvas(.zero), editor.transform.toCanvas(editor.visibleCanvasSize))
        for node in editor.graph.nodes.values {
            let frame = editor.frame(of: node)
            #expect(visible.contains(frame.origin) && visible.contains(frame.origin + frame.size), "\(node.name)")
        }
    }

    @Test func editsInsideLandInTheDefinitionAsOneUndoStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        let before = try #require(grouped.current?.graph.nodes[grouped.rectangle.id]?.position)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(30, 0))
        editor.pointerDragged(from: start, to: start + Vector2(60, 0))
        editor.pointerReleased(from: start, at: start + Vector2(60, 0))
        let moved = try #require(grouped.current?.graph.nodes[grouped.rectangle.id]?.position)
        #expect(moved != before)
        #expect(editor.rootGraph.nodes[grouped.rectangle.id] == nil, "nothing was added to the top level")
        editor.perform(.undo)
        #expect(grouped.current?.graph.nodes[grouped.rectangle.id]?.position == before, "the whole drag is one step")
        #expect(editor.document.canUndo, "the Group step is still there")
    }

    @Test func wiringInsideAGroupGoesToItsDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = try #require(grouped.definition.inputNode)
        let link = Link(from: Endpoint(node: input.id, socket: "width"), to: Endpoint(node: grouped.extrude.id, socket: "distance"))
        editor.connect(link)
        #expect(grouped.current?.graph.links.contains(link) == true)
        #expect(editor.rootGraph.links.contains(link) == false)
        editor.perform(.undo)
        #expect(grouped.current?.graph.links.contains(link) == false)
    }

    @Test func hitTestingAndDrawingSeeTheLevelShown() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.hitTest(editor.screenPoint(in: grouped.group)) == .node(grouped.group))
        editor.enterGroup(grouped.group)
        // Framed to fit, the level is small on screen: a point in the middle of the node, away from its sockets.
        let middle = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        #expect(editor.hitTest(middle) == .node(grouped.rectangle.id))
        #expect(Set(editor.drawnNodes.map(\.id)) == Set(grouped.definition.graph.nodes.keys))
    }

    @Test func undoingTheGroupWhileInsideFallsBackToTheLevelAround() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selectAll()
        editor.document.undo()
        #expect(editor.levelPath.isEmpty, "the group node is gone, so the level shown is the top level")
        #expect(editor.graph.nodes.count == 4 && editor.graphPath == .root)
        editor.refreshLevel()
        #expect(editor.enteredGroups.isEmpty && editor.selection.isEmpty)
        #expect(editor.document.inspectedLevel.isEmpty)
    }

    @Test func documentParametersStayOnTheTopLevelAndShowInsideToo() throws {
        let parameter = GraphParameter(name: "Width", type: .number, value: .number(10))
        let grouped = try GroupedEditor(parameters: [parameter])
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.inspectorPage.parameters.map(\.parameter.name) == ["Width"])
        editor.setParameter(parameter.id, to: .number(25))
        #expect(editor.rootGraph.parameters.first?.value == .number(25))
        editor.setParameterNumber(parameter.id, to: 30)
        #expect(editor.rootGraph.parameters.first?.value == .number(30))
        #expect(grouped.current?.graph.parameters.isEmpty == true)
    }

    @Test func nodesInsideShowTheirStatesFromTheDocumentsInnerResults() async throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        await editor.document.waitForEvaluation()
        #expect(editor.result(of: grouped.group)?.state.isSuccess == true)
        editor.enterGroup(grouped.group)
        await editor.document.waitForEvaluation()
        #expect(editor.result(of: grouped.rectangle.id)?.state.isSuccess == true)
        #expect(editor.result(of: grouped.group) == nil, "the group node is not on this level")
        #expect(Set(editor.levelResults.keys) == Set(grouped.definition.graph.nodes.keys))
    }
}
