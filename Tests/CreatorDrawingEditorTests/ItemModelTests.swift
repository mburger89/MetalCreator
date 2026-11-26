import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Item numbers, materials, part numbers and the remembered names (DR-5 R5, R16).
@MainActor
@Suite("Item model")
struct ItemModelTests {
    private struct Scene {
        let h: EditorHarness
        let parts: [NodeID]
    }

    private func open(_ names: [String], items: [PartItem] = []) -> Scene {
        let parts = names.map { _ in NodeID() }
        let view = DrawingView(
            kind: .base, source: parts[0], orientation: .standard(.front), center: .zero, assembly: parts)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        var document = EditorDocuments.document([sheet])
        document.items = items
        let h = EditorHarness(document: document, sheet: sheet.id)
        h.model.partFacts = Dictionary(
            uniqueKeysWithValues: zip(parts, names).map { ($0, PartFacts(name: $1, quantity: 1, isRemoved: false)) })
        return Scene(h: h, parts: parts)
    }

    private func numbers(_ h: EditorHarness) -> [NumberedItem] {
        PartItems.numbered(h.model.document, names: PartItems.names(of: h.model.partFacts))
    }

    @Test func settingAMaterialNeverRenumbers() throws {
        let s = open(["Bolt", "Nut", "Plate"])
        let before = numbers(s.h).map(\.part)
        s.h.model.setItemMaterial("S235", of: s.parts[2])
        #expect(s.h.log.commits.map(\.name) == ["Change Item"])
        #expect(s.h.model.document.items.map(\.part) == before)
        #expect(numbers(s.h).map(\.number) == [1, 2, 3])
        #expect(numbers(s.h).map(\.part) == before)
        #expect(numbers(s.h)[2].material == "S235")
    }

    @Test func aPartNumberIsTrimmed() throws {
        let s = open(["Bolt", "Nut"])
        s.h.model.setItemPartNumber("  M6-20  ", of: s.parts[0])
        #expect(numbers(s.h).first { $0.part == s.parts[0] }?.partNumber == "M6-20")
        #expect(s.h.log.commits.map(\.name) == ["Change Item"])
    }

    @Test func movingAnItem() throws {
        let s = open(["Bolt", "Nut", "Plate"])
        let nut = s.parts[1]
        s.h.model.moveItem(nut, by: -1)
        #expect(s.h.log.commits.map(\.name) == ["Move Item"])
        #expect(numbers(s.h).map(\.part) == [s.parts[1], s.parts[0], s.parts[2]])
        #expect(numbers(s.h).number(of: nut) == 1)
    }

    @Test func movingPastTheEndDoesNothing() throws {
        let s = open(["Bolt", "Nut", "Plate"])
        s.h.model.moveItem(s.parts[0], by: -1)
        s.h.model.moveItem(s.parts[2], by: 1)
        #expect(s.h.log.commits.isEmpty)
        #expect(s.h.model.document.items.isEmpty)
    }

    @Test func sameValueNoCommit() throws {
        let s = open(["Bolt", "Nut"])
        s.h.model.setItemMaterial("", of: s.parts[0])
        s.h.model.setItemMaterial("S235", of: s.parts[0])
        s.h.model.setItemMaterial("S235", of: s.parts[0])
        s.h.model.setItemPartNumber("", of: s.parts[1])
        #expect(s.h.log.commits.count == 1)
    }

    @Test func aNewPartFollowsThePinned() throws {
        let s = open(["Bolt", "Nut", "Plate"])
        s.h.model.setItemMaterial("S235", of: s.parts[0])
        let axle = NodeID()
        var document = s.h.model.document
        var view = document.sheets[0].views[0]
        view.assembly = s.parts + [axle]
        document.sheets[0].setView(view)
        s.h.model.replaceDocument(document)
        s.h.model.partFacts[axle] = PartFacts(name: "Axle", quantity: 1, isRemoved: false)
        #expect(numbers(s.h).number(of: axle) == 4)
    }

    @Test func pinningKeepsTheNumbersShown() throws {
        // Plate, Bolt and Nut live; Axle's Output is gone but remembered.
        let s = open(["Plate", "Bolt", "Nut", "Axle"])
        s.h.model.partFacts[s.parts[3]] = PartFacts(name: "Axle", quantity: nil, isRemoved: true)
        let before = numbers(s.h)
        s.h.model.setItemMaterial("S235", of: s.parts[2])
        let after = numbers(s.h)
        #expect(before.map(\.part) == after.map(\.part))
        #expect(before.map(\.number) == after.map(\.number))
        #expect(s.h.model.document.items.map(\.part) == before.map(\.part))
    }

    @Test func rememberedNamesAreSaved() throws {
        let s = open(["Bolt", "Nut"])
        let gone = NodeID()
        s.h.model.rememberPartNames([s.parts[0]: "Bolt", gone: "Gone"])
        #expect(s.h.log.commits.isEmpty)
        let saved = s.h.model.documentForSaving()
        #expect(saved.partNames == [PartName(part: s.parts[0], name: "Bolt")])
        #expect(s.h.log.commits.isEmpty)
        #expect(s.h.model.document.partNames.isEmpty)
    }

    @Test func openingSeedsRememberedNames() throws {
        let part = NodeID()
        let view = DrawingView(kind: .base, source: part, orientation: .standard(.front), center: .zero)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        var document = EditorDocuments.document([sheet])
        document.partNames = [PartName(part: part, name: "Plate")]
        let h = EditorHarness(document: document, sheet: sheet.id)
        #expect(h.model.rememberedPartNames == [part: "Plate"])
        let other = NodeID()
        var next = document
        next.partNames = [PartName(part: other, name: "Other")]
        h.model.replaceDocument(next)
        #expect(h.model.rememberedPartNames[other] == "Other")
        #expect(h.model.rememberedPartNames[part] == "Plate")
    }
}
