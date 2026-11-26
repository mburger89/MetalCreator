import Foundation
import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("View placement")
struct ViewPlacementTests {
    private let node = NodeID()

    private func base(_ at: Vector2) -> DrawingView {
        DrawingView(kind: .base, source: node, orientation: .standard(.front), center: at)
    }

    private func child(of parent: DrawingView, axis: AlignmentAxis, at: Vector2) -> DrawingView {
        DrawingView(
            kind: .projected, source: node, orientation: .standard(.right), center: at,
            alignment: ViewAlignment(parent: parent.id, axis: axis))
    }

    private func sheet(_ views: [DrawingView]) -> DrawingSheet { DrawingSheet(name: "Sheet 1", views: views) }

    @Test func childrenShareTheirParentsCoordinate() {
        let parent = base(Vector2(100, 100))
        let side = child(of: parent, axis: .horizontal, at: Vector2(180, 130))
        let above = child(of: parent, axis: .vertical, at: Vector2(130, 170))
        let centers = ViewPlacement.centers(in: sheet([parent, side, above]))
        #expect(centers[side.id] == Vector2(180, 100))
        #expect(centers[above.id] == Vector2(100, 170))
    }

    @Test func movingAParentCarriesItsChildren() {
        let parent = base(Vector2(100, 100))
        let side = child(of: parent, axis: .horizontal, at: Vector2(180, 100))
        let grand = child(of: side, axis: .vertical, at: Vector2(180, 160))
        let moved = ViewPlacement.moving(parent.id, by: Vector2(10, 5), in: sheet([parent, side, grand]))
        let centers = ViewPlacement.centers(in: moved)
        #expect(centers[parent.id] == Vector2(110, 105))
        #expect(centers[side.id] == Vector2(190, 105))
        #expect(centers[grand.id] == Vector2(190, 165))
    }

    @Test func draggingAChildSlidesAlongItsAxis() {
        let parent = base(Vector2(100, 100))
        let side = child(of: parent, axis: .horizontal, at: Vector2(180, 100))
        let moved = ViewPlacement.moving(side.id, by: Vector2(15, 30), in: sheet([parent, side]))
        let centers = ViewPlacement.centers(in: moved)
        #expect(centers[side.id] == Vector2(195, 100))
        #expect(centers[parent.id] == Vector2(100, 100))
    }

    @Test func switchingTheStandardMirrorsChildren() {
        let parent = base(Vector2(100, 100))
        let side = child(of: parent, axis: .horizontal, at: Vector2(180, 100))
        let grand = child(of: side, axis: .vertical, at: Vector2(180, 150))
        let original = sheet([parent, side, grand])
        let mirrored = ViewPlacement.mirroredForStandardChange(original)
        let centers = ViewPlacement.centers(in: mirrored)
        #expect(centers[parent.id] == Vector2(100, 100))
        #expect(centers[side.id] == Vector2(20, 100))
        #expect(centers[grand.id]?.x == 20)
        #expect(centers[grand.id] == Vector2(20, 50))
        #expect(mirrored.view(side.id)?.orientation == side.orientation)
        #expect(mirrored.view(grand.id)?.alignment == grand.alignment)
    }

    @Test func removingAParentFreesChildren() {
        let parent = base(Vector2(100, 100))
        let side = child(of: parent, axis: .horizontal, at: Vector2(180, 130))
        let removed = ViewPlacement.removing(parent.id, from: sheet([parent, side]))
        #expect(removed.view(parent.id) == nil)
        #expect(removed.view(side.id)?.alignment == nil)
        #expect(removed.view(side.id)?.center == Vector2(180, 100))
    }

    @Test func aCycleFreesOnlyTheHigherIDAndTheOtherFollowsIt() {
        var a = base(Vector2(10, 20))
        var b = base(Vector2(50, 60))
        a.alignment = ViewAlignment(parent: b.id, axis: .horizontal)
        b.alignment = ViewAlignment(parent: a.id, axis: .vertical)
        var built = DrawingSheet(name: "Sheet 1")
        built.setView(a)
        built.setView(b)
        let centers = ViewPlacement.centers(in: built)
        let (low, high) = a.id < b.id ? (a, b) : (b, a)
        #expect(centers[high.id] == high.center)
        let axis = low.alignment?.axis
        let expected = axis == .horizontal ? Vector2(low.center.x, high.center.y) : Vector2(high.center.x, low.center.y)
        #expect(centers[low.id] == expected)
    }

    private func section(of parent: DrawingView, aligned: AlignmentAxis?, at: Vector2) -> DrawingView {
        let cutter = SectionCutter(
            frame: StandardOrientation.front.frame, points: [Vector2(0, 0), Vector2(10, 0)], viewing: Vector2(0, 1))
        return DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: at,
            alignment: aligned.map { ViewAlignment(parent: parent.id, axis: $0) },
            derivation: .section(SectionLine(parent: parent.id, cutter: cutter)), letter: "A")
    }

    private func detail(of parent: DrawingView, at: Vector2) -> DrawingView {
        DrawingView(
            kind: .detail, source: node, orientation: .standard(.front), center: at,
            derivation: .detail(DetailCircle(parent: parent.id, center: .zero, radius: 3)), letter: "B")
    }

    @Test func freeDerivedViewsMoveWithTheirParent() {
        let parent = base(Vector2(100, 100))
        let slanted = section(of: parent, aligned: nil, at: Vector2(300, 200))
        let enlarged = detail(of: parent, at: Vector2(250, 40))
        let nested = detail(of: enlarged, at: Vector2(330, 40))
        let moved = ViewPlacement.moving(parent.id, by: Vector2(10, 5), in: sheet([parent, slanted, enlarged, nested]))
        let centers = ViewPlacement.centers(in: moved)
        #expect(centers[parent.id] == Vector2(110, 105))
        #expect(centers[slanted.id] == Vector2(310, 205))
        #expect(centers[enlarged.id] == Vector2(260, 45))
        #expect(centers[nested.id] == Vector2(340, 45))
    }

    @Test func anAlignedSectionSlidesAlongItsAxis() {
        let parent = base(Vector2(100, 100))
        let straight = section(of: parent, aligned: .vertical, at: Vector2(100, 30))
        let moved = ViewPlacement.moving(straight.id, by: Vector2(7, -4), in: sheet([parent, straight]))
        let centers = ViewPlacement.centers(in: moved)
        #expect(centers[straight.id] == Vector2(100, 26), "only along its free axis")
        #expect(centers[parent.id] == Vector2(100, 100))
    }

    @Test func removingAParentFreesAlignedSections() {
        let parent = base(Vector2(100, 100))
        let straight = section(of: parent, aligned: .vertical, at: Vector2(140, 30))
        let enlarged = detail(of: parent, at: Vector2(250, 40))
        let result = ViewPlacement.removing(parent.id, from: sheet([parent, straight, enlarged]))
        #expect(result.view(parent.id) == nil)
        let freed = result.view(straight.id)
        #expect(freed?.alignment == nil)
        #expect(freed?.center == Vector2(100, 30), "where it stood")
        #expect(freed?.derivation != nil, "still a section of the deleted view")
        #expect(result.view(enlarged.id)?.derivation != nil)
    }

    @Test func aDerivationCycleDoesNotLoop() {
        let a = base(Vector2(0, 0))
        var first = detail(of: a, at: Vector2(10, 10))
        var second = detail(of: first, at: Vector2(20, 20))
        first.derivation = .detail(DetailCircle(parent: second.id, center: .zero, radius: 1))
        second.derivation = .detail(DetailCircle(parent: first.id, center: .zero, radius: 1))
        let moved = ViewPlacement.moving(first.id, by: Vector2(1, 1), in: sheet([a, first, second]))
        #expect(moved.view(second.id)?.center == Vector2(21, 21))
    }
}

@Suite("View alignment repair")
struct ViewAlignmentRepairTests {
    private let node = NodeID()

    private func view(_ id: ViewID, aligned parent: ViewID?) -> DrawingView {
        DrawingView(
            id: id, kind: .projected, source: node, orientation: .standard(.right), center: Vector2(10, 10),
            alignment: parent.map { ViewAlignment(parent: $0, axis: .horizontal) })
    }

    private func decoded(_ views: [DrawingView]) throws -> DrawingSheet {
        let sheet = DrawingSheet(name: "S", views: views)
        return try JSONDecoder().decode(DrawingSheet.self, from: JSONEncoder().encode(sheet))
    }

    private func ids() -> (ViewID, ViewID, ViewID) {
        let sorted = [ViewID(), ViewID(), ViewID()].sorted()
        return (sorted[0], sorted[1], sorted[2])
    }

    @Test func aMissingGrandparentFreesOnlyTheViewBesideIt() throws {
        let (a, b, c) = ids()
        let sheet = try decoded([view(b, aligned: a), view(c, aligned: b)])
        #expect(sheet.view(b)?.alignment == nil)
        #expect(sheet.view(c)?.alignment?.parent == b)
        // The unrepaired sheet places the same way: c still follows b's height.
        var free = view(b, aligned: a)
        free.center = Vector2(10, 30)
        var follower = view(c, aligned: b)
        follower.center = Vector2(70, 5)
        let centers = ViewPlacement.centers(in: DrawingSheet(name: "S", views: [free, follower]))
        #expect(centers[b] == Vector2(10, 30))
        #expect(centers[c] == Vector2(70, 30))
    }

    @Test func aTwoViewCycleFreesTheHigherID() throws {
        let (low, high, _) = ids()
        let sheet = try decoded([view(low, aligned: high), view(high, aligned: low)])
        #expect(sheet.view(high)?.alignment == nil)
        #expect(sheet.view(low)?.alignment?.parent == high)
    }

    @Test func aViewLeadingIntoACycleKeepsItsAlignment() throws {
        let (a, b, c) = ids()
        let sheet = try decoded([view(a, aligned: b), view(b, aligned: a), view(c, aligned: a)])
        #expect(sheet.view(b)?.alignment == nil)
        #expect(sheet.view(a)?.alignment?.parent == b)
        #expect(sheet.view(c)?.alignment?.parent == a)
    }

    @Test func aCycleInAnUnrepairedSheetFreesTheHigherIDOnly() {
        let (low, high, _) = ids()
        let raw = DrawingSheet(name: "S", views: [view(low, aligned: high), view(high, aligned: low)])
        let centers = ViewPlacement.centers(in: raw)
        #expect(centers[high] == Vector2(10, 10) && centers[low] == Vector2(10, 10))
    }
}
