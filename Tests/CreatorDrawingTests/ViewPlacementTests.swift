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

    @Test func aCycleLeavesViewsFree() {
        var a = base(Vector2(10, 20))
        var b = base(Vector2(50, 60))
        a.alignment = ViewAlignment(parent: b.id, axis: .horizontal)
        b.alignment = ViewAlignment(parent: a.id, axis: .vertical)
        var built = DrawingSheet(name: "Sheet 1")
        built.setView(a)
        built.setView(b)
        let centers = ViewPlacement.centers(in: built)
        #expect(centers[a.id] == Vector2(10, 20))
        #expect(centers[b.id] == Vector2(50, 60))
    }
}
