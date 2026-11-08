import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorEditor

/// The node library's sub-groups and its Grouped / A–Z switch, through the model's real entries.
@MainActor
struct LibraryGroupingTests {
    func editor(sort: LibrarySort = .grouped) -> EditorModel {
        let document = DocumentModel(file: GraphFile(viewState: ViewState(dock: .bottom, librarySort: sort)),
                                     registry: BuiltInNodes.registry, kernel: FakeKernel())
        return EditorModel(document: document)
    }

    func run(_ model: EditorModel, _ category: NodeCategory) -> [[String]] {
        model.librarySections.first { $0.category == category }?.subgroups.map { $0.entries.map(\.displayName) } ?? []
    }

    @Test func groupedIsTheDefault() {
        #expect(editor().librarySort == .grouped)
    }

    @Test func groupedFieldsAreSourcesMathsAndUsing() {
        #expect(run(editor(), .fields) == [
            ["Distance Field", "Image Field", "Linear Gradient", "Noise Field", "Radial Gradient"],
            ["Add", "Clamp", "Min / Max", "Multiply", "Remap", "Smooth Blend"],
            ["Cull by Field", "Field Scatter", "Sample Field"],
        ])
    }

    @Test func alphabeticalHasOneRunAndNoHeadings() {
        let model = editor(sort: .alphabetical)
        let runs = run(model, .fields)
        #expect(runs.count == 1)
        #expect(runs[0] == runs[0].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(!model.libraryItems.contains { $0.subgroupTitle != nil })
    }

    @Test func everyNodeNamesASubgroupItsCategoryHas() {
        for definition in BuiltInNodes.all {
            let names = definition.category.librarySubgroups
            if let name = definition.librarySubgroup {
                #expect(names.contains(name), "\(definition.displayName): \(name)")
            } else {
                #expect(names.isEmpty, "\(definition.displayName) is in a sub-grouped category with no sub-group")
            }
        }
    }

    @Test func rowsPutAHeadingBeforeEachRun() {
        let rows = editor().libraryItems
        let titles = rows.compactMap(\.subgroupTitle)
        #expect(titles.starts(with: ["Numbers", "Geometry"]))
        let index = rows.firstIndex { $0.subgroupTitle == "Layouts" }
        #expect(index.map { rows[$0 - 1].id == "header.patterns" } == true)
    }

    @Test func searchKeepsTheHeadingsOfRunsThatMatch() {
        let model = editor()
        model.setLibraryQuery("cull")
        let rows = model.libraryItems
        let fields = rows.filter { $0.category == .fields }.map(\.subgroupTitle)
        #expect(fields.compactMap { $0 } == ["Using"], "Sources and Maths have no match, so their headings are gone")
        #expect(rows.compactMap(\.subgroupTitle).contains("Variation"))
    }

    @Test func aTypeWithNoSubgroupGoesAfterTheNamedOnesUnheaded() {
        let entries = [
            PaletteEntry(typeID: "a", displayName: "A", category: .patterns),
            PaletteEntry(typeID: "b", displayName: "B", category: .patterns, subgroup: "Placing"),
        ]
        let section = LibrarySection.grouping(entries, sort: .grouped)[0]
        #expect(section.subgroups.map(\.title) == ["Placing", nil])
        #expect(section.entries.map(\.typeID) == ["b", "a"])
    }

    @Test func theSwitchIsViewStateNotAnEdit() throws {
        let model = editor()
        model.setLibrarySort(.alphabetical)
        #expect(model.librarySort == .alphabetical)
        #expect(!model.document.canUndo)
        let data = try model.document.fileData()
        let reopened = EditorModel(document: try DocumentModel(data: data, registry: BuiltInNodes.registry, kernel: FakeKernel()))
        #expect(reopened.librarySort == .alphabetical)
        model.setLibrarySort(.grouped)
        let json = try JSONSerialization.jsonObject(with: model.document.fileData()) as? [String: Any]
        let state = json?["viewState"] as? [String: Any]
        #expect(state?["librarySort"] == nil, "Grouped is the absent key")
    }

    @Test func theHeadingsDrawGroupedAndNotAlphabetical() {
        func glyphs(_ sort: LibrarySort) -> Int {
            let model = editor(sort: sort)
            let input = GraphPanelInput(model: model)
            return renderHeadless { GraphPanel(model: model, input: input) }.glyphs.count
        }
        #expect(glyphs(.grouped) >= glyphs(.alphabetical) + "NumbersGeometry".count)
    }
}
