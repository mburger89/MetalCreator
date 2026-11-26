import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Item numbers are computed from the document and the parts' names (DR-5 R5).
@Suite("Part items")
struct PartItemsTests {
    private let plate = NodeID(), bolt = NodeID(), nut = NodeID(), fourth = NodeID()

    private func view(_ outputs: [NodeID]) -> DrawingView {
        DrawingView(
            kind: .base, source: outputs[0], orientation: .standard(.top), center: .zero,
            assembly: outputs.count > 1 ? outputs : nil)
    }

    private func balloon(on part: NodeID, in view: DrawingView) -> DrawingAnnotation {
        let topology = AnnotationFixtures.topology()
        let leader = LeaderEnd(target: .onPart(part, AnnotationFixtures.pick(topology, 102)), hint: .zero)
        return DrawingAnnotation(view: view.id, kind: .balloon(Balloon(leader: leader, offset: Vector2(10, 10))))
    }

    private func document(_ outputs: [NodeID], items: [PartItem] = []) -> DrawingDocument {
        DrawingDocument(sheets: [DrawingSheet(name: "Sheet 1", views: [view(outputs)])], items: items)
    }

    private var names: [NodeID: String] { [plate: "Plate", bolt: "Bolt", nut: "Nut"] }

    private func numbers(_ items: [NumberedItem]) -> [NodeID] { items.sorted { $0.number < $1.number }.map(\.part) }

    @Test func wantedFollowsSheetsViewsAndParts() {
        // A sheet's views are kept sorted by ID, so the order inside one sheet is fixed by the document, not by the test.
        let assembly = view([plate, bolt])
        let sheetOne = DrawingSheet(name: "One", views: [assembly], annotations: [balloon(on: fourth, in: assembly)])
        let sheetTwo = DrawingSheet(name: "Two", views: [view([nut])])
        let sheetThree = DrawingSheet(name: "Three", views: [view([plate])])
        let wanted = PartItems.wanted(in: DrawingDocument(sheets: [sheetOne, sheetTwo, sheetThree]))
        #expect(wanted == [plate, bolt, fourth, nut])
        let both = DrawingSheet(name: "Both", views: [view([nut]), view([bolt, plate])])
        let found = PartItems.wanted(in: DrawingDocument(sheets: [both]))
        #expect(found == both.views.flatMap(\.outputs).reduce(into: [NodeID]()) { if !$0.contains($1) { $0.append($1) } })
    }

    @Test func unpinnedPartsGoByName() {
        let items = PartItems.numbered(document([plate, bolt, nut]), names: names)
        #expect(numbers(items) == [bolt, nut, plate])
        #expect(items.map(\.number).sorted() == [1, 2, 3])
        #expect(items.number(of: bolt) == 1 && items.number(of: nut) == 2 && items.number(of: plate) == 3)
    }

    @Test func equalNamesGoByNodeID() {
        let low = NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let items = PartItems.numbered(document([high, low]), names: [low: "Same", high: "Same"])
        #expect(numbers(items) == [low, high])
    }

    @Test func pinnedPartsComeFirst() {
        let items = PartItems.numbered(document([plate, bolt, nut], items: [PartItem(part: plate)]), names: names)
        #expect(numbers(items) == [plate, bolt, nut])
    }

    @Test func numbersHaveNoGaps() {
        let gone = NodeID()
        let items = PartItems.numbered(
            document([plate, bolt], items: [PartItem(part: gone, material: "Brass"), PartItem(part: plate)]), names: names)
        #expect(numbers(items) == [plate, bolt])
        #expect(items.map(\.number).sorted() == [1, 2])
        #expect(items.number(of: gone) == nil)
    }

    @Test func aRemovedPartKeepsItsNumber() {
        var facts: [NodeID: PartFacts] = [
            plate: PartFacts(name: "Plate", quantity: 1, isRemoved: false),
            bolt: PartFacts(name: "Bolt", quantity: 1, isRemoved: false),
            nut: PartFacts(name: "Nut", quantity: 1, isRemoved: false),
        ]
        let doc = document([plate, bolt, nut])
        let before = PartItems.numbered(doc, names: PartItems.names(of: facts))
        facts[plate] = PartFacts(name: "Plate", quantity: nil, isRemoved: true)
        let after = PartItems.numbered(doc, names: PartItems.names(of: facts))
        #expect(numbers(before) == [bolt, nut, plate] && numbers(after) == [bolt, nut, plate])
        facts[bolt] = PartFacts(name: "Bolt", quantity: nil, isRemoved: true)
        let both = PartItems.numbered(doc, names: PartItems.names(of: facts))
        #expect(both.number(of: bolt) == 1 && both.number(of: nut) == 2 && both.number(of: plate) == 3)
    }

    @Test func aPartWithNoNameSortsLast() {
        let ghost = NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        let assembly = view([plate, bolt, nut])
        let sheet = DrawingSheet(name: "One", views: [assembly], annotations: [balloon(on: ghost, in: assembly)])
        let facts: [NodeID: PartFacts] = [
            plate: PartFacts(name: "Plate", quantity: 1, isRemoved: false),
            bolt: PartFacts(name: "Bolt", quantity: 1, isRemoved: false),
            nut: PartFacts(name: "Nut", quantity: 1, isRemoved: false),
            ghost: PartFacts(name: "?", quantity: nil, isRemoved: true),
        ]
        let found = PartItems.names(of: facts)
        #expect(found[ghost] == nil && found.count == 3)
        let items = PartItems.numbered(DrawingDocument(sheets: [sheet]), names: found)
        #expect(numbers(items) == [bolt, nut, plate, ghost])
    }

    @Test func editingAnItemPinsTheOrder() {
        let stale = PartItem(part: fourth, material: "Brass", partNumber: "X-1")
        let doc = document(
            [plate, bolt, nut], items: [PartItem(part: nut, material: "Steel", partNumber: "N-9"), stale])
        let pinned = PartItems.pinningOrder(doc, names: names)
        #expect(pinned.map(\.part) == [nut, bolt, plate, fourth])
        #expect(pinned[0].material == "Steel" && pinned[0].partNumber == "N-9")
        #expect(pinned[3] == stale)
        let again = PartItems.numbered(DrawingDocument(sheets: doc.sheets, items: pinned), names: names)
        #expect(numbers(again) == [nut, bolt, plate])
    }

    @Test func aPartWithNoBalloonIsListed() {
        let items = PartItems.numbered(document([plate]), names: names)
        #expect(items.count == 1 && items[0].number == 1 && items[0].part == plate)
    }
}
