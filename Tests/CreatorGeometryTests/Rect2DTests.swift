import Testing
@testable import CreatorGeometry

struct Rect2DTests {
    @Test func unionAndContains() {
        let a = Rect2D(min: Vector2(0, 0), max: Vector2(2, 2))
        let b = Rect2D(min: Vector2(1, -1), max: Vector2(5, 1))
        let both = a.union(b)
        #expect(both.min == Vector2(0, -1))
        #expect(both.max == Vector2(5, 2))
        #expect(both.contains(Vector2(5, 2)))
        #expect(!both.contains(Vector2(5.1, 0)))
        #expect(a.intersects(b))
        #expect(!a.intersects(Rect2D(min: Vector2(3, 3), max: Vector2(4, 4))))
        #expect(both.width == 5 && both.height == 3)
        #expect(both.center == Vector2(2.5, 0.5))
    }

    @Test func insetGrowsWhenNegative() {
        let rect = Rect2D(min: Vector2(0, 0), max: Vector2(10, 10))
        #expect(rect.insetBy(1) == Rect2D(min: Vector2(1, 1), max: Vector2(9, 9)))
        #expect(rect.insetBy(-1) == Rect2D(min: Vector2(-1, -1), max: Vector2(11, 11)))
    }

    @Test func pointsGiveTheirBox() {
        #expect(Rect2D(points: []) == nil)
        let box = Rect2D(points: [Vector2(1, 5), Vector2(-2, 3), Vector2(4, -1)])
        #expect(box == Rect2D(min: Vector2(-2, -1), max: Vector2(4, 5)))
    }
}
