import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

struct SolidDimensionTests {
    /// A 20 × 10 rectangle on XY, centred, so its bounds are (−10, −5)–(10, 5).
    func extrudeGraph(_ values: [SocketName: ConstantValue]) -> (Harness, Node) {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let extrude = h.add(ExtrudeNode.self, values)
        h.wire(rectangle, "profile", to: extrude, "profile")
        return (h, extrude)
    }

    struct Linear {
        var from: Vector3, to: Vector3, direction: Vector3, side: Vector3
        var placement: DimensionPlacement
    }

    func linear(_ spec: DimensionSpec) throws -> Linear {
        guard case let .linear(from, to, direction, side, placement) = spec.geometry else {
            Issue.record("expected a linear dimension, got \(spec.geometry)")
            throw CancellationError()
        }
        return Linear(from: from, to: to, direction: direction, side: side, placement: placement)
    }

    @Test func anExtrudeDimensionsItsDistanceFromTheProfilesCorner() async throws {
        let (h, extrude) = extrudeGraph(["distance": .number(10)])
        let report = try await h.run([extrude])
        let specs = try #require(report.results[extrude.id]?.dimensions)
        let spec = try #require(specs.first)
        #expect(specs.count == 1)
        #expect(spec.target == .input("distance"))
        #expect(spec.quantity == .length)
        #expect(spec.value == 10)
        let geometry = try linear(spec)
        #expect(isClose(geometry.from, Vector3(10, -5, 0)) && isClose(geometry.to, Vector3(10, -5, 10)))
        #expect(isClose(geometry.direction, .unitZ) && isClose(geometry.side, .unitX))
        #expect(geometry.placement == .standoff)
    }

    @Test func reversedAndSymmetricExtrudesMoveTheBase() async throws {
        let (hr, reversed) = extrudeGraph(["distance": .number(10), "reversed": .bool(true)])
        let r = try linear(try #require(try await hr.run([reversed]).results[reversed.id]?.dimensions.first))
        #expect(isClose(r.from, Vector3(10, -5, -10)) && isClose(r.to, Vector3(10, -5, 0)))
        let (hs, symmetric) = extrudeGraph(["distance": .number(10), "mode": .integer(1)])
        let s = try linear(try #require(try await hs.run([symmetric]).results[symmetric.id]?.dimensions.first))
        #expect(isClose(s.from, Vector3(10, -5, -5)) && isClose(s.to, Vector3(10, -5, 5)))
    }

    #if canImport(CreatorOCCT)
    // FakeKernel cannot revolve, so this one runs on the real kernel.
    @Test func aRevolveDimensionsItsAngleButNotAFullTurn() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self, ["plane": .plane(.xz)])
        let partial = h.add(RevolveNode.self, ["angle": .number(90), "axisOrigin": .vector(Vector3(-20, 0, 0)),
                                               "axisDirection": .vector(.unitZ),
        ])
        let full = h.add(RevolveNode.self, ["angle": .number(360), "axisOrigin": .vector(Vector3(-20, 0, 0)),
                                            "axisDirection": .vector(.unitZ),
        ])
        h.wire(rectangle, "profile", to: partial, "profile")
        h.wire(rectangle, "profile", to: full, "profile")
        let report = try await h.run([partial, full], kernel: OCCTKernel())
        let spec = try #require(report.results[partial.id]?.dimensions.first)
        #expect(report.results[partial.id]?.dimensions.count == 1)
        #expect(spec.target == .input("angle") && spec.quantity == .angle && spec.value == 90)
        guard case let .angular(vertex, first, second, normal, placement) = spec.geometry else {
            Issue.record("expected an angular dimension")
            return
        }
        // Centre of the profile is the origin; its projection on the axis x = −20 is (−20, 0, 0).
        #expect(isClose(vertex, Vector3(-20, 0, 0)) && isClose(first, .zero))
        #expect(isClose(second, Vector3(-20, 0, 0) + Vector3(20, 0, 0).rotated(about: .unitZ, by: .degrees(90))))
        #expect(isClose(normal, .unitZ) && placement == .standoff)
        #expect(report.results[full.id]?.dimensions == [])
    }
    #endif

    @Test func aRectangleDimensionsWidthAndHeight() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let specs = try #require(try await h.run([rectangle]).results[rectangle.id]?.dimensions)
        #expect(specs.map(\.target) == [.input("width"), .input("height")])
        #expect(specs.map(\.value) == [20, 10])
        let (w, ht) = (try linear(specs[0]), try linear(specs[1]))
        #expect(isClose(w.from, Vector3(-10, -5, 0)) && isClose(w.to, Vector3(10, -5, 0)))
        #expect(isClose(w.direction, .unitX) && isClose(w.side, -.unitY))
        #expect(isClose(ht.from, Vector3(10, -5, 0)) && isClose(ht.to, Vector3(10, 5, 0)))
        #expect(isClose(ht.direction, .unitY) && isClose(ht.side, .unitX))
    }

    @Test func aCircleDimensionsItsDiameter() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(8)])
        let specs = try #require(try await h.run([circle]).results[circle.id]?.dimensions)
        let spec = try #require(specs.first)
        #expect(specs.count == 1 && spec.target == .input("diameter") && spec.quantity == .diameter && spec.value == 8)
        guard case let .radial(center, radius, normal, toward, placement) = spec.geometry else {
            Issue.record("expected a radial dimension")
            return
        }
        #expect(isClose(center, .zero) && isClose(radius, 4) && isClose(normal, .unitZ) && placement == .standoff)
        #expect(isClose(toward, Vector3(1, 1, 0) * (1 / 2.0.squareRoot())))
    }

    @Test func broadcastingAnExtrudeGivesOneSpecPerProfile() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self)
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(5)])
        let points = h.add(GridPointsNode.self)
        h.wire(points, "points", to: circle, "plane")
        h.wire(circle, "profile", to: extrude, "profile")
        let specs = try #require(try await h.run([extrude]).results[extrude.id]?.dimensions)
        #expect(specs.count > 1)
        #expect(Set(specs.map(\.target)) == [.input("distance")])
    }
}
