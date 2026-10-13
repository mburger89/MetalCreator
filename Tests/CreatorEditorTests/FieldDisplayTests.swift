import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// Fields in the editor (fields spec §2.1 and §4): the inspector's "Field" row, the socket tooltip, the undo names and the
/// refusal of a field wired into a number socket.
@MainActor
struct FieldDisplayTests {
    let registry = BuiltInNodes.registry

    func node(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        var made = registry.makeNode(definition.typeID)
        made.inputValues.merge(values) { _, given in given }
        made.isOutput = true  // only output nodes are demanded; this one is evaluated
        return made
    }

    func editor(_ nodes: [Node], _ links: [Link] = []) async -> EditorModel {
        let editor = makeEditor(nodes, links, registry: registry)
        await editor.document.waitForEvaluation()
        return editor
    }

    func fieldSection(_ editor: EditorModel, _ node: Node) -> InspectorSectionRows? {
        editor.selection = [node.id]
        return editor.inspectorPage.sections.first { $0.title == "Field" }
    }

    // MARK: the inspector's Field row

    @Test func aNodeWithAFieldOutputShowsItsRecipe() async {
        let radial = node(RadialGradientNode.self, ["radius": .number(7.5)])
        let editor = await editor([radial])
        let expected = InspectorSectionRows(title: "Field", rows: [.recipe(label: "Field", text: "radial(radius 7.5)")])
        #expect(fieldSection(editor, radial) == expected)
    }

    @Test func theRecipeFollowsTheWiringAndIsTheLastSection() async {
        let noise = node(NoiseFieldNode.self, ["seed": .integer(4)])
        let remap = node(FieldRemapNode.self, ["fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(1), "toHigh": .number(0)])
        let editor = await editor([noise, remap], [wire(noise, "field", remap, "field")])
        let section = fieldSection(editor, remap)
        #expect(section?.rows == [.recipe(label: "Field", text: "remap(noise(seed 4, scale 10, octaves 1), 0…20 → 1…0)")])
        #expect(editor.inspectorPage.sections.last?.title == "Field")
    }

    @Test func aNodeThatMakesNoFieldHasNoFieldRow() async {
        let number = node(NumberNode.self)
        let sample = node(SampleFieldNode.self)
        let cull = node(CullByFieldNode.self)
        let editor = await editor([number, sample, cull])
        for other in [number, sample, cull] {
            #expect(fieldSection(editor, other) == nil, "\(other.name)")
        }
    }

    @Test func beforeAResultTheRowSaysSo() {
        let radial = node(RadialGradientNode.self)
        let graph = Graph(nodes: [radial.id: radial], links: [], parameters: [])
        let page = InspectorBuilder.page(graph: graph, selection: [radial.id], registry: registry, results: [:])
        #expect(page.sections.last == InspectorSectionRows(title: "Field", rows: [.recipe(label: "Field", text: "No field yet")]))
    }

    @Test func anEvaluatedResultWithoutAFieldSaysSoAccurately() {
        let radial = node(RadialGradientNode.self)
        let graph = Graph(nodes: [radial.id: radial], links: [], parameters: [])
        let mixed = Value.list([.field(.constant(1)), .number(2)])
        for value in [Value.list([]), mixed] {
            let results = [radial.id: NodeResult(state: .ok(duration: .zero), outputs: ["field": value])]
            let page = InspectorBuilder.page(graph: graph, selection: [radial.id], registry: registry, results: results)
            let expected = InspectorSectionRows(title: "Field", rows: [.recipe(label: "Field", text: "No field in this result")])
            #expect(page.sections.last == expected)
        }
    }

    @Test func aListOfFieldsIsCounted() async {
        let series = node(SeriesNode.self, ["count": .integer(3)])
        let add = node(FieldAddNode.self, ["b": .number(10)])
        let editor = await editor([series, add], [wire(series, "values", add, "a")])
        #expect(fieldSection(editor, add)?.rows == [.recipe(label: "Field", text: "3 fields")])
    }

    @Test func theRecipeRowDrawsHeadlessly() async {
        let radial = node(RadialGradientNode.self)
        let editor = await editor([radial])
        editor.selection = [radial.id]
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
    }

    // MARK: socket tooltips

    @Test func anOutputAndTheInputItIsWiredIntoShowTheRecipe() async {
        let noise = node(NoiseFieldNode.self, ["seed": .integer(4)])
        let multiply = node(FieldMultiplyNode.self, ["b": .number(0.5)])
        let editor = await editor([noise, multiply], [wire(noise, "field", multiply, "a")])
        #expect(editor.socketHelp(of: noise.id) == ["out.field": "noise(seed 4, scale 10, octaves 1)"])
        let help = editor.socketHelp(of: multiply.id)
        #expect(help["in.a"] == "noise(seed 4, scale 10, octaves 1)")
        #expect(help["in.b"] == nil, "a typed number has no tooltip")
        #expect(help["out.field"] == "noise(seed 4, scale 10, octaves 1) × 0.5")
    }

    @Test func aLongRecipeIsCutToEightyCharacters() async {
        var nodes: [Node] = [node(NoiseFieldNode.self)]
        var links: [Link] = []
        for _ in 0..<6 {
            let add = node(FieldAddNode.self, ["b": .number(12345.5)])
            links.append(wire(nodes[nodes.count - 1], "field", add, "a"))
            nodes.append(add)
        }
        let editor = await editor(nodes, links)
        let help = editor.socketHelp(of: nodes[nodes.count - 1].id)["out.field"]
        #expect(help?.count == 80 && help?.hasSuffix("…") == true, "\(String(describing: help))")
    }

    @Test func numbersAndSamplesHaveNoFieldTooltip() async {
        let number = node(NumberNode.self)
        let editor = await editor([number])
        #expect(editor.socketHelp(of: number.id).isEmpty)
    }

    @Test func aListOfFieldsShowsItsCount() async {
        let series = node(SeriesNode.self, ["count": .integer(3)])
        let add = node(FieldAddNode.self)
        let editor = await editor([series, add], [wire(series, "values", add, "a")])
        #expect(editor.socketHelp(of: add.id)["out.field"] == "3 fields")
    }

    // MARK: undo names and typed numbers

    @Test func addingFieldNodesNamesTheStepAfterTheType() {
        let editor = makeEditor([], registry: registry)
        _ = editor.addFromLibrary(FieldRemapNode.typeID)
        #expect(editor.document.undoName == "Add Remap")
        _ = editor.addFromLibrary(DistanceFieldNode.typeID)
        #expect(editor.document.undoName == "Add Distance Field")
    }

    /// Decision 9: the spec's names, so adding these two reads "Undo Add Add" and "Undo Add Multiply". Pinned here so that choosing
    /// "Add Fields" and "Multiply Fields" instead is a visible change to these lines and to the node's display names.
    @Test func addingAddOrMultiplyReadsOddlyAndIsPinned() {
        let editor = makeEditor([], registry: registry)
        _ = editor.addFromLibrary(FieldAddNode.typeID)
        #expect(editor.document.undoName == "Add Add")
        _ = editor.addFromLibrary(FieldMultiplyNode.typeID)
        #expect(editor.document.undoName == "Add Multiply")
    }

    @Test func aNumberTypedIntoAFieldSocketIsStoredAsANumberAndNamedByItsLabel() async throws {
        let multiply = node(FieldMultiplyNode.self)
        let editor = await editor([multiply])
        editor.selection = [multiply.id]
        let rows = try #require(editor.inspectorPage.sections.first?.rows)
        guard case .number(let b) = rows[1] else {
            Issue.record("expected a number row for b")
            return
        }
        editor.setNumber(b, to: 0.5)
        #expect(editor.graph.nodes[multiply.id]?.inputValues["b"] == .number(0.5))
        #expect(editor.document.undoName == "Change B")
        await editor.document.waitForEvaluation()
        editor.selection = [multiply.id]
        #expect(editor.inspectorPage.sections.last?.rows == [.recipe(label: "Field", text: "1 × 0.5")])
    }

    @Test func remapsInputsAreNamedByTheirLabels() async throws {
        let remap = node(FieldRemapNode.self)
        let editor = await editor([remap])
        editor.selection = [remap.id]
        let rows = editor.inspectorPage.sections.first?.rows ?? []
        guard case .number(let fromLow)? = rows.first else {
            Issue.record("expected a number row")
            return
        }
        editor.setNumber(fromLow, to: 2)
        #expect(editor.document.undoName == "Change From low")
    }

    @Test func cullByFieldsSegmentedInputsAreNamedByTheirLabels() async throws {
        let cull = node(CullByFieldNode.self)
        let editor = await editor([cull])
        editor.selection = [cull.id]
        let sections = editor.inspectorPage.sections
        guard case .segmented(let mode, _, _)? = sections.first(where: { $0.title == "Cull" })?.rows.first,
              case .segmented(let keep, _, _)? = sections.first(where: { $0.title == "Threshold" })?.rows.last else {
            Issue.record("expected segmented rows for mode and keep")
            return
        }
        editor.setInput(mode, to: .integer(1))
        #expect(editor.document.undoName == "Change Mode")
        editor.setInput(keep, to: .integer(1))
        #expect(editor.document.undoName == "Change Keep")
    }

    // MARK: refusing a field where a number goes

    @Test func aFieldCannotBeWiredIntoANumberInput() async {
        let radial = node(RadialGradientNode.self)
        let circle = node(CircleNode.self)
        let editor = await editor([radial, circle])
        editor.connect(wire(radial, "field", circle, "diameter"))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal?.message == "A field can't connect to a number input.")
    }

    @Test func aNumberCanBeWiredIntoAFieldInputInOneNamedStep() async {
        let number = node(NumberNode.self)
        let add = node(FieldAddNode.self)
        let editor = await editor([number, add])
        editor.connect(wire(number, "value", add, "a"))
        #expect(editor.graph.links.count == 1 && editor.refusal == nil)
        #expect(editor.document.undoName == "Connect")
    }
}
