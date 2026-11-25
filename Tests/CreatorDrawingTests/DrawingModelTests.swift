import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

private func requireSendable<T: Sendable>(_: T.Type) {}

private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func makeView(_ id: ViewID = ViewID(), alignment: ViewAlignment? = nil, center: Vector2 = Vector2(10, 20)) -> DrawingView {
    DrawingView(
        id: id, kind: alignment == nil ? .base : .projected, source: NodeID(), orientation: .standard(.front), scale: nil,
        center: center, alignment: alignment)
}

@Suite("Drawing model")
struct DrawingModelTests {
    @Test func aDocumentRoundTrips() throws {
        let base = makeView()
        let custom = DrawingView(
            id: ViewID(), kind: .projected, source: NodeID(),
            orientation: .custom(ProjectionFrame(direction: Vector3(1, 0, 0), up: Vector3(0, 0, 1))),
            scale: DrawingScale(numerator: 1, denominator: 2), center: Vector2(50, 60),
            alignment: ViewAlignment(parent: base.id, axis: .horizontal), showsHidden: true, showsTangent: false, showsLabel: true)
        let third = makeView(center: Vector2(1, 2))
        var first = DrawingSheet(name: "Sheet 1")
        first.titleBlock.density = 7.85
        first.titleBlock.owner = "ACME"
        for view in [base, custom] { first.setView(view) }
        var second = DrawingSheet(name: "Sheet 2", size: .ansiB, orientation: .portrait)
        second.setView(third)
        let document = DrawingDocument(settings: DrawingSettings(standard: .asme), sheets: [first, second])
        let back = try JSONDecoder().decode(DrawingDocument.self, from: encoded(document))
        #expect(back == document)
        #expect(!back.isEmpty)
        #expect(back.sheet(second.id) == second)
    }

    @Test func sheetsKeepTheirOrder() throws {
        let ids = [SheetID(), SheetID(), SheetID()]
        let sorted = ids.sorted()
        let order = [sorted[2], sorted[0], sorted[1]]
        let sheets = order.map { DrawingSheet(id: $0, name: "S") }
        let back = try JSONDecoder().decode(DrawingDocument.self, from: encoded(DrawingDocument(sheets: sheets)))
        #expect(back.sheets.map(\.id) == order)
    }

    @Test func viewsAreSortedById() throws {
        let views = (0..<5).map { _ in makeView() }.sorted { $0.id < $1.id }
        var sheet = DrawingSheet(name: "S")
        for view in views.reversed() { sheet.setView(view) }
        #expect(sheet.views.map(\.id) == views.map(\.id))
        let back = try JSONDecoder().decode(DrawingSheet.self, from: encoded(sheet))
        #expect(back.views.map(\.id) == views.map(\.id))
        sheet.removeView(views[0].id)
        #expect(sheet.view(views[0].id) == nil)
        #expect(sheet.views.count == 4)
    }

    @Test func emptyTitleFieldsAreNotWritten() throws {
        var block = TitleBlock()
        block.title = "Bracket"
        let text = try #require(String(data: encoded(block), encoding: .utf8))
        #expect(!text.contains("owner"))
        #expect(!text.contains("density"))
        #expect(text.contains("title"))
        #expect(try JSONDecoder().decode(TitleBlock.self, from: encoded(block)) == block)
    }

    @Test func aDanglingAlignmentIsDropped() throws {
        let ghost = ViewID()
        let orphan = makeView(alignment: ViewAlignment(parent: ghost, axis: .vertical), center: Vector2(33, 44))
        var sheet = DrawingSheet(name: "S")
        sheet.setView(orphan)
        let back = try JSONDecoder().decode(DrawingDocument.self, from: encoded(DrawingDocument(sheets: [sheet])))
        let kept = try #require(back.sheets[0].view(orphan.id))
        #expect(kept.alignment == nil)
        #expect(kept.center == Vector2(33, 44))
    }

    @Test func anAlignmentCycleIsDropped() throws {
        let a = ViewID(), b = ViewID()
        var sheet = DrawingSheet(name: "S")
        sheet.setView(makeView(a, alignment: ViewAlignment(parent: b, axis: .horizontal)))
        sheet.setView(makeView(b, alignment: ViewAlignment(parent: a, axis: .horizontal)))
        let back = try JSONDecoder().decode(DrawingDocument.self, from: encoded(DrawingDocument(sheets: [sheet])))
        #expect(back.sheets[0].views.count == 2)
        #expect(back.sheets[0].views.contains { $0.alignment == nil })
        #expect(back.sheets[0].views.filter { $0.alignment != nil }.count <= 1)
    }

    @Test func everyModelTypeIsSendable() {
        requireSendable(SheetID.self)
        requireSendable(ViewID.self)
        requireSendable(DrawingStandard.self)
        requireSendable(SheetSize.self)
        requireSendable(SheetOrientation.self)
        requireSendable(DrawingScale.self)
        requireSendable(StandardOrientation.self)
        requireSendable(ViewOrientation.self)
        requireSendable(ViewKind.self)
        requireSendable(AlignmentAxis.self)
        requireSendable(ViewAlignment.self)
        requireSendable(DrawingView.self)
        requireSendable(TitleBlock.self)
        requireSendable(DrawingSheet.self)
        requireSendable(DrawingSettings.self)
        requireSendable(DrawingDocument.self)
        requireSendable(DrawingStyle.self)
    }

    @Test func landscapeSwapsTheSize() {
        let sheet = DrawingSheet(name: "S", size: .a3, orientation: .landscape)
        #expect(sheet.paperSize == Vector2(420, 297))
        #expect(DrawingSheet(name: "S", size: .a3, orientation: .portrait).paperSize == Vector2(297, 420))
        #expect(SheetSize.ansiB.title == "B")
        #expect(SheetSize.a3.title == "A3")
        #expect(SheetSize.a2.isLarge && SheetSize.ansiC.isLarge && !SheetSize.a3.isLarge && !SheetSize.ansiB.isLarge)
    }

    @Test func preferredScalesAreISO5455() {
        let pairs = [(50, 1), (20, 1), (10, 1), (5, 1), (2, 1), (1, 1), (1, 2), (1, 5), (1, 10), (1, 20), (1, 50), (1, 100), (1, 200),
                     (1, 500), (1, 1000),
        ]
        #expect(DrawingScale.preferred.map { [$0.numerator, $0.denominator] } == pairs.map { [$0.0, $0.1] })
        #expect(DrawingScale(numerator: 1, denominator: 4).value == 0.25)
        #expect(DrawingScale(numerator: 1, denominator: 1000).isValid)
        #expect(!DrawingScale(numerator: 0, denominator: 1).isValid)
        #expect(!DrawingScale(numerator: 1, denominator: 1001).isValid)
    }

    @Test func scaleText() {
        #expect(DrawingScale(numerator: 1, denominator: 2).text(for: .iso) == "1 : 2")
        #expect(DrawingScale(numerator: 2, denominator: 1).text(for: .iso) == "2 : 1")
        #expect(DrawingScale(numerator: 1, denominator: 2).text(for: .asme) == "1:2")
    }

    @Test func orientationFrames() {
        let expected: [(StandardOrientation, Vector3, Vector3)] = [
            (.front, Vector3(0, 1, 0), Vector3(0, 0, 1)), (.back, Vector3(0, -1, 0), Vector3(0, 0, 1)),
            (.left, Vector3(1, 0, 0), Vector3(0, 0, 1)), (.right, Vector3(-1, 0, 0), Vector3(0, 0, 1)),
            (.top, Vector3(0, 0, -1), Vector3(0, 1, 0)), (.bottom, Vector3(0, 0, 1), Vector3(0, -1, 0)),
        ]
        for (orientation, direction, up) in expected {
            #expect(orientation.frame.direction == direction)
            #expect(orientation.frame.up == up)
        }
        for orientation in StandardOrientation.allCases {
            let frame = orientation.frame
            #expect(abs(frame.direction.length - 1) < 1e-12)
            #expect(abs(frame.up.length - 1) < 1e-12)
            #expect(abs(frame.direction.dot(frame.up)) < 1e-12)
        }
        #expect(StandardOrientation.front.title == "Front")
        #expect(StandardOrientation.isometricFrontLeft.title == "Isometric")
    }

    @Test func isometricFramesAreIsometric() {
        for orientation in StandardOrientation.allCases {
            #expect(orientation.isIsometric == (orientation == .isometricFrontRight || orientation == .isometricFrontLeft))
            #expect(ViewOrientation.standard(orientation).isIsometric == orientation.isIsometric)
        }
        let r = 1 / 3.0.squareRoot()
        #expect(abs(StandardOrientation.isometricFrontRight.frame.direction.x + r) < 1e-12)
        #expect(abs(StandardOrientation.isometricFrontLeft.frame.direction.x - r) < 1e-12)
        #expect(!ViewOrientation.custom(StandardOrientation.top.frame).isIsometric)
        #expect(ViewOrientation.custom(StandardOrientation.isometricFrontRight.frame).isIsometric)
    }

    @Test func defaultTolerances() {
        #expect(DrawingSettings.defaultTolerance(for: .iso, inches: false) == "ISO 2768-mK")
        #expect(DrawingSettings.defaultTolerance(for: .asme, inches: false) == "±0.5, ±0.1, ±0.05 mm")
        #expect(DrawingSettings.defaultTolerance(for: .asme, inches: true) == "±.03, ±.010, ±.005 in")
        #expect(DrawingSettings().generalTolerance == "ISO 2768-mK")
        #expect(DrawingStandard.iso.isFirstAngle && !DrawingStandard.asme.isFirstAngle)
    }
}
