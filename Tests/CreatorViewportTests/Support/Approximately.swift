// Test fixture file: approximate comparisons shared by the viewport tests.
import CreatorGeometry
@testable import CreatorViewport

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance * max(1, abs(a), abs(b))
}

func isClose(_ a: Vector3, _ b: Vector3, tolerance: Double = 1e-6) -> Bool {
    (a - b).length <= tolerance * max(1, a.length, b.length)
}

func isClose(_ a: ScreenPoint, _ b: ScreenPoint, tolerance: Double = 1e-6) -> Bool {
    (a - b).length <= tolerance * max(1, a.length, b.length)
}

/// The eight corners of a box.
func corners(_ box: BoundingBox) -> [Vector3] {
    (0..<8).map { i in
        Vector3(i & 1 == 0 ? box.min.x : box.max.x, i & 2 == 0 ? box.min.y : box.max.y, i & 4 == 0 ? box.min.z : box.max.z)
    }
}
