import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct InspectorTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero, values: ["width": .number(60)])
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let number = testNode(NumberTestNode.self, id: 3, at: Vector2(0, 300))
    let parameter = GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)

    @Test func nothingSelectedShowsOnlyTheDocumentParameters() {
        let editor = makeEditor([rect], parameters: [parameter])
        let page = editor.inspectorPage
        #expect(page.header == nil)
        #expect(page.sections.isEmpty)
        #expect(page.parameters == [ParameterRow(parameter: parameter, range: 10...200)])
    }

    @Test func severalSelectedShowsOnlyTheDocumentParameters() {
        let editor = makeEditor([rect, extrude], parameters: [parameter])
        editor.selection = [rect.id, extrude.id]
        #expect(editor.inspectorPage.header == nil)
        #expect(editor.inspectorPage.parameters.count == 1)
    }

    @Test func unwiredControlsBindToTheStoredValueOrTheDefault() {
        let editor = makeEditor([rect], parameters: [parameter])
        editor.selection = [rect.id]
        let page = editor.inspectorPage
        #expect(page.header == InspectorHeader(node: rect.id, title: "Rectangle", category: .profile, state: nil))
        #expect(page.sections.map(\.title) == ["Size", "Placement"])
        let width = InputField(node: rect.id, socket: "width", label: "Width", type: .number, unit: .millimetres, value: .number(60))
        let height = InputField(node: rect.id, socket: "height", label: "Height", type: .number, unit: .millimetres, value: .number(10))
        #expect(page.sections[0].rows == [.slider(width, range: 0...100), .slider(height, range: 0...100)])
        let plane = InputField(node: rect.id, socket: "plane", label: "Plane", type: .plane, unit: .none, value: .plane(.xy))
        let anchor = InputField(node: rect.id, socket: "anchor", label: "Anchor", type: .integer, unit: .none, value: .integer(4))
        #expect(page.sections[1].rows == [.planePicker(plane, selected: .xy), .anchorGrid(anchor, selected: 4)])
        #expect(page.parameters.count == 1)
    }

    @Test func aWiredInputShowsWhereItIsWiredFrom() {
        var source = number
        source.name = "Edges ∥ Z"
        let editor = makeEditor([source, rect], [wire(source, "value", rect, "width")])
        editor.selection = [rect.id]
        #expect(editor.inspectorPage.sections[0].rows.first == .wired(label: "Width", source: "wired from Edges ∥ Z"))
    }

    @Test func sliderRangesComeFromTheSocketAndWidenToTheValue() {
        let editor = makeEditor([testNode(ExtrudeTestNode.self, id: 4, at: .zero, values: ["distance": .number(250)])])
        editor.selection = [nodeID(4)]
        guard case .slider(_, let range)? = editor.inspectorPage.sections[0].rows.dropFirst().first else {
            Issue.record("no slider"); return
        }
        #expect(range == 0...250)
    }

    /// M3's Extrude "Reverse direction" is a toggle on a bool *socket* (spec Errata (M3)), unlike
    /// Fillet's `showHandle` setting: it reads the socket default and writes a stored `.bool`.
    @Test func aSocketToggleReadsItsDefaultAndWritesABool() {
        let editor = makeEditor([extrude])
        editor.selection = [extrude.id]
        guard case .toggle(let field, let label)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(label == "Reverse direction")
        #expect(field.socket == "reversed" && field.type == .bool && field.value == .bool(false) && !field.isOptional)
        editor.setInput(field, to: .bool(true))
        #expect(editor.graph.nodes[extrude.id]?.inputValues["reversed"] == .bool(true))
    }

    /// M3's Grid Points `total` (also Edge Filter `maxLength`, Transform `axisDirection`) is an
    /// optional input with no default: it starts unset, can be set, and can be cleared again.
    @Test func anOptionalInputStartsUnsetAndCanBeCleared() throws {
        let grid = testNode(GridPointsTestNode.self, id: 8, at: .zero)
        let editor = makeEditor([grid], registry: inspectorTestRegistry)
        editor.selection = [grid.id]
        func totalField() -> InputField? {
            guard case .integer(let field)? = editor.inspectorPage.sections.first?.rows.last else { return nil }
            return field
        }
        let unset = try #require(totalField())
        #expect(unset.socket == "total" && unset.isOptional && unset.value == nil)
        editor.clearInput(unset)
        #expect(!editor.document.canUndo)
        editor.setNumber(unset, to: 6)
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == .integer(6))
        editor.clearInput(try #require(totalField()))
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == nil)
        editor.document.undo()
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == .integer(6))
        // A required input is never cleared: it would only fall back to its default silently.
        guard case .integer(let countX)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no countX row"); return
        }
        #expect(!countX.isOptional)
        editor.setNumber(countX, to: 3)
        editor.clearInput(countX)
        #expect(editor.graph.nodes[grid.id]?.inputValues["countX"] == .integer(3))
    }

    @Test func segmentedControlsReadAndWriteTheSocketsOwnType() {
        let editor = makeEditor([testNode(ExtrudeTestNode.self, id: 4, at: .zero, values: ["mode": .integer(1)])])
        editor.selection = [nodeID(4)]
        guard case .segmented(_, let options, let selected)? = editor.inspectorPage.sections[0].rows.first else {
            Issue.record("no segmented control"); return
        }
        #expect(options == ["Distance", "Symmetric"])
        #expect(selected == 1)
        #expect(InspectorBuilder.segmentValue(0, options: options, type: .integer) == .integer(0))
        #expect(InspectorBuilder.segmentValue(1, options: ["Off", "On"], type: .bool) == .bool(true))
        #expect(InspectorBuilder.segmentValue(1, options: ["A", "B"], type: nil) == .text("B"))
        #expect(InspectorBuilder.segmentValue(2, options: options, type: .integer) == nil)
        #expect(InspectorBuilder.segmentIndex(.text("B"), options: ["A", "B"]) == 1)
        #expect(InspectorBuilder.segmentIndex(.bool(false), options: ["Off", "On"]) == 0)
    }

    @Test func ruleSummaryCountsTheEdgesItsRuleMatched() async {
        let profile = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let solid = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(600, 0))
        var fillet = testNode(FilletTestNode.self, id: 4, at: Vector2(900, 0))
        fillet.isOutput = true
        let editor = makeEditor([profile, solid, edges, fillet], [
            wire(profile, "profile", solid, "profile"), wire(solid, "solid", edges, "solid"),
            wire(solid, "solid", fillet, "solid"), wire(edges, "edges", fillet, "edges"),
        ])
        await editor.document.waitForEvaluation()
        editor.selection = [fillet.id]
        let page = editor.inspectorPage
        #expect(page.sections.map(\.title) == ["Fillet", "Edges"])
        #expect(page.sections[1].rows == [
            .ruleSummary(label: "Edges", summary: "All Edges · 12 edges"),
            .button(title: "Pick edges in view…", action: .pickEdgesInView),
        ])
        guard case .toggle(_, let label)? = page.sections[0].rows.last else { Issue.record("no toggle"); return }
        #expect(label == "Show handle in view")
    }

    @Test func anUnconnectedRuleSaysSo() {
        let editor = makeEditor([testNode(FilletTestNode.self, id: 4, at: .zero)])
        editor.selection = [nodeID(4)]
        #expect(editor.inspectorPage.sections[1].rows.first == .ruleSummary(label: "Edges", summary: "No rule connected"))
    }

    /// M3's selection-rule nodes put `ruleSummary("edges")` on their own *output*.
    @Test func aRuleNodeSummarisesItsOwnOutput() async {
        let profile = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let solid = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        var edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(600, 0))
        edges.isOutput = true
        let editor = makeEditor([profile, solid, edges],
                                [wire(profile, "profile", solid, "profile"), wire(solid, "solid", edges, "solid")])
        editor.selection = [edges.id]
        let unevaluated = InspectorSectionRows(title: "Edges", rows: [.ruleSummary(label: "Edges", summary: "No result yet")])
        #expect(editor.inspectorPage.sections == [unevaluated])
        await editor.document.waitForEvaluation()
        #expect(editor.inspectorPage.sections[0].rows == [.ruleSummary(label: "Edges", summary: "12 edges")])
    }

    /// M3's `showHandle` is a setting, not a socket. `makeNode` seeds it `.bool(true)` through
    /// `defaultSettings`; a node without it (a hand-edited file) still reads On.
    @Test func aSettingToggleReadsOnWhenAbsent() {
        let fillet = testNode(FilletTestNode.self, id: 4, at: .zero)
        #expect(fillet.inputValues[NodeSetting.showHandle] == .bool(true))
        var bare = testNode(FilletTestNode.self, id: 5, at: Vector2(0, 300))
        bare.inputValues[NodeSetting.showHandle] = nil
        let editor = makeEditor([fillet, bare])
        editor.selection = [fillet.id]
        guard case .toggle(let field, let label)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(label == "Show handle in view")
        #expect(field.socket == NodeSetting.showHandle && field.type == .bool && field.value == .bool(true))
        editor.setInput(field, to: .bool(false))
        #expect(editor.graph.nodes[fillet.id]?.inputValues[NodeSetting.showHandle] == .bool(false))
        editor.document.undo()
        #expect(editor.graph.nodes[fillet.id]?.inputValues[NodeSetting.showHandle] == .bool(true))
        editor.selection = [bare.id]
        guard case .toggle(let bareField, _)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(bareField.value == .bool(true))
    }

    @Test func aVectorControlEditsOneComponent() {
        let transform = testNode(TransformTestNode.self, id: 5, at: .zero)
        let editor = makeEditor([transform], registry: inspectorTestRegistry)
        editor.selection = [transform.id]
        let field = InputField(node: transform.id, socket: "move", label: "Move", type: .vector, unit: .millimetres,
                               value: .vector(.zero))
        #expect(editor.inspectorPage.sections == [InspectorSectionRows(title: "Move", rows: [.vector(field)])])
        editor.setVectorComponent(field, axis: 1, to: 5)
        #expect(editor.graph.nodes[transform.id]?.inputValues["move"] == .vector(Vector3(0, 5, 0)))
        #expect(InspectorBuilder.vectorValue(.vector(Vector3(1, 2, 3)), axis: 2, to: 9) == .vector(Vector3(1, 2, 9)))
        #expect(InspectorBuilder.vectorValue(nil, axis: 3, to: 9) == nil)
    }

    /// M3's Graph Parameter stores `ConstantValue.parameter(id)` under `NodeSetting.parameter`.
    @Test func aParameterPickerListsTheDocumentParametersAndWritesTheID() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let node = testNode(GraphParameterTestNode.self, id: 6, at: .zero)
        let editor = makeEditor([node], parameters: [parameter, count], registry: inspectorTestRegistry)
        editor.selection = [node.id]
        guard case .parameterPicker(let field, let options, let selected)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no parameter picker"); return
        }
        #expect(field.socket == NodeSetting.parameter && field.type == nil && field.value == nil)
        #expect(options.map(\.name) == ["Width", "Hole count"])
        #expect(selected == nil)
        editor.chooseParameter(count.id, for: field)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.parameter] == .parameter(count.id))
        guard case .parameterPicker(_, _, let chosen)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no parameter picker"); return
        }
        #expect(chosen == count.id)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.parameter]?.parameterID == count.id)
    }

    @Test func aDefinitionWithoutAnInspectorGetsOneRowPerSimpleInput() {
        let editor = makeEditor([number])
        editor.selection = [number.id]
        let field = InputField(node: number.id, socket: "value", label: "Value", type: .number, unit: .millimetres, value: .number(5))
        #expect(editor.inspectorPage.sections == [InspectorSectionRows(title: "Inputs", rows: [.slider(field, range: 0...50)])])
    }

    @Test func aMissingNodeSaysItsTypeIsUnavailable() {
        let missing = Node(id: nodeID(7), typeID: "plugin.gone", name: "Gone")
        let editor = makeEditor([missing])
        editor.selection = [missing.id]
        let note = InspectorSectionRows(title: "Missing node",
                                        rows: [.readOnly(label: "Type", text: "“plugin.gone” isn't available")])
        #expect(editor.inspectorPage.sections == [note])
    }

    @Test func pressingAnInspectorButtonRecordsARequestForTheViewport() {
        let editor = makeEditor([testNode(FilletTestNode.self, id: 4, at: .zero)])
        editor.press(.pickEdgesInView, on: nodeID(4))
        editor.press(.pickEdgesInView, on: nodeID(4))
        #expect(editor.inspectorRequest == InspectorRequest(node: nodeID(4), action: .pickEdgesInView, serial: 2))
    }
}
