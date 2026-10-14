import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// Implicit solids in the editor (implicit spec §2.1, §5.2): the inspector's "Implicit" row and the socket tooltip.
@MainActor
struct ImplicitDisplayTests {
    let registry = BuiltInNodes.registry

    func node(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        var made = registry.makeNode(definition.typeID)
        made.inputValues.merge(values) { _, given in given }
        made.isOutput = true
        return made
    }

    func editor(_ nodes: [Node], _ links: [Link] = []) async -> EditorModel {
        let editor = makeEditor(nodes, links, registry: registry)
        await editor.document.waitForEvaluation()
        return editor
    }

    func section(_ editor: EditorModel, _ node: Node, _ title: String) -> InspectorSectionRows? {
        editor.selection = [node.id]
        return editor.inspectorPage.sections.first { $0.title == title }
    }

    @Test func aNodeWithAnImplicitOutputShowsItsRecipe() async {
        let sphere = node(ImplicitSphereNode.self, ["radius": .number(7.5)])
        let editor = await editor([sphere])
        #expect(section(editor, sphere, "Implicit") == InspectorSectionRows(title: "Implicit", rows: [
            .recipe(label: "Implicit", text: "sphere(radius 7.5 mm)"),
        ]))
    }

    @Test func theRecipeFollowsTheWiring() async {
        let sphere = node(ImplicitSphereNode.self)
        let shell = node(ImplicitShellNode.self)
        let editor = await editor([sphere, shell], [wire(sphere, "implicit", shell, "implicit")])
        #expect(section(editor, shell, "Implicit")?.rows == [.recipe(label: "Implicit", text: "shell(sphere(radius 10 mm), inward 2 mm)")])
    }

    @Test func beforeAResultTheRowSaysSo() {
        let sphere = node(ImplicitSphereNode.self)
        let editor = makeEditor([sphere], [], registry: registry)
        #expect(section(editor, sphere, "Implicit")?.rows == [.recipe(label: "Implicit", text: "No implicit solid yet")])
    }

    @Test func aNodeThatMakesNoImplicitHasNoImplicitRow() async {
        let number = node(NumberNode.self)
        let editor = await editor([number])
        #expect(section(editor, number, "Implicit") == nil && section(editor, number, "Mesh") == nil)
    }

    @Test func theTooltipShowsTheRecipeOnTheOutputAndOnTheInputItIsWiredInto() async {
        let sphere = node(ImplicitSphereNode.self)
        let union = node(ImplicitUnionNode.self)
        let editor = await editor([sphere, union], [wire(sphere, "implicit", union, "shapes")])
        #expect(editor.socketHelp(of: sphere.id)["out.implicit"] == "sphere(radius 10 mm)")
        #expect(editor.socketHelp(of: union.id)["in.shapes"] == "sphere(radius 10 mm)")
    }

    @Test func aLongRecipeIsCutToEightyCharacters() async {
        let sphere = node(ImplicitSphereNode.self)
        var chain = [sphere]
        var links: [Link] = []
        for step in 0..<4 {
            let next = node(step.isMultiple(of: 2) ? ImplicitShellNode.self : ImplicitOffsetNode.self)
            links.append(wire(chain[chain.count - 1], "implicit", next, "implicit"))
            chain.append(next)
        }
        let editor = await editor(chain, links)
        let tip = editor.socketHelp(of: chain[chain.count - 1].id)["out.implicit"]
        #expect(tip?.count == 80 && tip?.hasSuffix("…") == true)
    }
}
