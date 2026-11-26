import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorDrawing

/// DR-5 Task 1: assembly views, part anchors, balloons, tables, items, part names and logos in the model.
struct AssemblyModelTests {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    private func pick(_ node: NodeID) -> EdgePick {
        let start = TopoTag(node: node, item: 0, role: .startCap), end = TopoTag(node: node, item: 0, role: .endCap)
        return EdgePick(key: EdgeKey([start], [end]), matchCount: 1)
    }

    private func view(_ source: NodeID, assembly: [NodeID]? = nil) -> DrawingView {
        DrawingView(kind: .base, source: source, orientation: .standard(.front), center: Vector2(50, 50), assembly: assembly)
    }

    @Test func assemblyRoundTrips() throws {
        let a = NodeID(), b = NodeID(), c = NodeID()
        let assembly = view(a, assembly: [a, b, c])
        let back = try roundTrip(assembly)
        #expect(back == assembly)
        #expect(back.outputs == [a, b, c])
        #expect(back.isAssembly)
        #expect(try object(assembly)["assembly"] != nil)
        let single = view(a)
        #expect(try object(single)["assembly"] == nil)
        #expect(single.outputs == [a])
        #expect(!single.isAssembly)
    }

    @Test func assemblyIsRepaired() throws {
        let a = NodeID(), b = NodeID()
        var empty = try object(view(a, assembly: [a, b]))
        empty["assembly"] = [String]()
        let emptyData = try JSONSerialization.data(withJSONObject: empty)
        let readEmpty = try JSONDecoder().decode(DrawingView.self, from: emptyData)
        #expect(readEmpty.assembly == nil)
        #expect(readEmpty.source == a)

        var repeated = try object(view(a, assembly: [a, b]))
        repeated["assembly"] = [b, a, b].map { $0.rawValue.uuidString }
        let repeatedData = try JSONSerialization.data(withJSONObject: repeated)
        let read = try JSONDecoder().decode(DrawingView.self, from: repeatedData)
        #expect(read.assembly == [b, a])
        #expect(read.source == b)
    }

    @Test func onPartRoundTrips() throws {
        let part = NodeID(), node = NodeID()
        let target = AnchorTarget.onPart(part, .edge(pick(node)))
        let written = try object(target)
        #expect(written["type"] as? String == "onPart")
        #expect(written["part"] as? String == part.rawValue.uuidString)
        #expect(written["target"] != nil)
        #expect(try roundTrip(target) == target)
        #expect(target.part == part)
        #expect(target.unwrapped == .edge(pick(node)))
        #expect(AnchorTarget.point(Vector2(1, 2)).part == nil)
    }

    @Test func nestedOnPartIsFlattened() throws {
        let a = NodeID(), b = NodeID(), node = NodeID()
        let nested = AnchorTarget.onPart(a, .onPart(b, .edge(pick(node))))
        #expect(try roundTrip(nested) == .onPart(b, .edge(pick(node))))
        let point = AnchorTarget.onPart(a, .point(Vector2(1, 2)))
        #expect(try roundTrip(point) == .point(Vector2(1, 2)))
    }

    @Test func balloonsAndTablesRoundTrip() throws {
        let part = NodeID(), node = NodeID()
        let shown = view(part)
        let balloon = DrawingAnnotation(
            view: shown.id,
            kind: .balloon(Balloon(leader: LeaderEnd(target: .onPart(part, .edge(pick(node))), hint: Vector2(1, 1)),
                                   offset: Vector2(8, 6))))
        let standing = DrawingAnnotation(view: nil, kind: .partsList(PartsList()))
        let rows = [RevisionRow(letter: "A", description: "First", date: "2026-11-26", approved: "MB"),
                    RevisionRow(letter: "B", description: "Second", date: "", approved: ""), ]
        let table = DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: rows, topRight: Vector2(400, 280))))
        let sheet = DrawingSheet(name: "S", views: [shown], annotations: [balloon, standing, table])
        let back = try roundTrip(sheet)
        #expect(back == sheet)
        #expect(back.partsList?.list.bottomRight == nil)
        #expect(back.revisionTable?.table.rows == rows)
        let free = DrawingAnnotation(view: nil, kind: .partsList(PartsList(bottomRight: Vector2(200, 50))))
        #expect(try roundTrip(DrawingSheet(name: "T", annotations: [free])).partsList?.list.bottomRight == Vector2(200, 50))
    }

    @Test func aSecondTableIsDropped() throws {
        let lists = [AnnotationID(), AnnotationID()].sorted()
        let tables = [AnnotationID(), AnnotationID()].sorted()
        let annotations = lists.map { DrawingAnnotation(id: $0, view: nil, kind: .partsList(PartsList())) }
            + tables.map { DrawingAnnotation(id: $0, view: nil, kind: .revisionTable(RevisionTable())) }
        let back = try roundTrip(DrawingSheet(name: "S", annotations: annotations))
        #expect(back.annotations.count == 2)
        #expect(back.partsList?.id == lists[0])
        #expect(back.revisionTable?.id == tables[0])
    }

    @Test func aBalloonWithoutAViewIsDropped() throws {
        let leader = LeaderEnd(target: .point(Vector2(0, 0)), hint: Vector2(0, 0))
        let balloon = DrawingAnnotation(view: nil, kind: .balloon(Balloon(leader: leader, offset: Vector2(5, 5))))
        #expect(try roundTrip(DrawingSheet(name: "S", annotations: [balloon])).annotations.isEmpty)
    }

    @Test func aTableWithAViewReadsFree() throws {
        let shown = view(NodeID())
        let list = DrawingAnnotation(view: shown.id, kind: .partsList(PartsList()))
        let table = DrawingAnnotation(view: shown.id, kind: .revisionTable(RevisionTable()))
        let back = try roundTrip(DrawingSheet(name: "S", views: [shown], annotations: [list, table]))
        #expect(back.annotations.count == 2)
        #expect(back.annotations.allSatisfy { $0.view == nil })
    }

    @Test func itemsAreWrittenOnlyWhenSet() throws {
        let empty = DrawingDocument(sheets: [DrawingSheet(name: "S")])
        #expect(try object(empty)["items"] == nil)
        let a = NodeID(), b = NodeID()
        let items = [PartItem(part: b, material: "Steel", partNumber: "P-2"), PartItem(part: a, material: "", partNumber: "")]
        let document = DrawingDocument(sheets: [DrawingSheet(name: "S")], items: items)
        #expect(try roundTrip(document).items == items)
        let twice = DrawingDocument(items: items + [PartItem(part: b, material: "Brass", partNumber: "X")])
        #expect(try roundTrip(twice).items == items)
    }

    @Test func partNamesAreWrittenOnlyWhenSet() throws {
        #expect(try object(DrawingDocument())["partNames"] == nil)
        let ids = [NodeID(), NodeID(), NodeID()].sorted()
        let names = [PartName(part: ids[2], name: "C"), PartName(part: ids[0], name: "A"), PartName(part: ids[1], name: "B"),
                     PartName(part: ids[0], name: "again"), ]
        let document = DrawingDocument(partNames: names)
        let back = try roundTrip(document)
        #expect(back.partNames == [PartName(part: ids[0], name: "A"), PartName(part: ids[1], name: "B"), PartName(part: ids[2], name: "C")])
        let written = try #require(try object(back)["partNames"] as? [[String: Any]])
        #expect(written.map { $0["part"] as? String } == ids.map { $0.rawValue.uuidString })
    }

    @Test func theLogoIsWrittenOnlyWhenSet() throws {
        #expect(try object(TitleBlock())["logo"] == nil)
        let hex = String(repeating: "ab", count: 32)
        let block = TitleBlock(owner: "Acme", logo: hex)
        #expect(try roundTrip(block).logo == hex)
        var damaged = try object(block)
        damaged["logo"] = String(repeating: "a", count: 63)
        let read = try JSONDecoder().decode(TitleBlock.self, from: JSONSerialization.data(withJSONObject: damaged))
        #expect(read.logo == nil)
        damaged["logo"] = String(repeating: "A", count: 64)
        #expect(try JSONDecoder().decode(TitleBlock.self, from: JSONSerialization.data(withJSONObject: damaged)).logo == nil)
    }

    @Test func revisionShownFollowsTheTable() {
        var sheet = DrawingSheet(name: "S", titleBlock: TitleBlock(revision: "typed"))
        #expect(sheet.revisionShown == "typed")
        let rows = [RevisionRow(letter: "A", description: "", date: "", approved: ""),
                    RevisionRow(letter: "B", description: "", date: "", approved: ""), ]
        sheet.setAnnotation(DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: rows))))
        #expect(sheet.revisionShown == "B")
        sheet.setAnnotation(DrawingAnnotation(id: sheet.revisionTable!.id, view: nil, kind: .revisionTable(RevisionTable())))
        #expect(sheet.revisionShown == "typed")
    }

    @Test func balloonPartIsItsWrapperOrTheSource() {
        let source = NodeID(), part = NodeID(), node = NodeID()
        let shown = view(source, assembly: [source, part])
        let wrapped = Balloon(leader: LeaderEnd(target: .onPart(part, .edge(pick(node))), hint: Vector2(0, 0)), offset: Vector2(5, 5))
        let bare = Balloon(leader: LeaderEnd(target: .edge(pick(node)), hint: Vector2(0, 0)), offset: Vector2(5, 5))
        #expect(wrapped.part(in: shown) == part)
        #expect(bare.part(in: shown) == source)
    }
}
