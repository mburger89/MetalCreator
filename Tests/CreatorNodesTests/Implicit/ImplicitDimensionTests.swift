import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import Testing
@testable import CreatorNodes

/// Box, Cylinder, Sphere and Shell dimension their sizes (spec §3.1, DIM-3 Task 7).
struct ImplicitDimensionTests {
    @Test func aBoxDimensionsEachSide() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 30, 40))])
        let specs = try #require(try await h.run([box]).results[box.id]?.dimensions)
        #expect(specs.count == 3 && specs.map(\.component) == [0, 1, 2] && specs.map(\.value) == [20, 30, 40])
        #expect(Set(specs.map(\.target)) == [.input("size")] && Set(specs.map(\.quantity)) == [.length])
        let expected: [(Vector3, Vector3, Vector3)] = [
            (Vector3(-10, -15, -20), Vector3(10, -15, -20), -.unitY),
            (Vector3(10, -15, -20), Vector3(10, 15, -20), .unitX),
            (Vector3(10, -15, -20), Vector3(10, -15, 20), .unitX),
        ]
        for (spec, want) in zip(specs, expected) {
            guard case let .linear(from, to, direction, side, _) = spec.geometry else {
                Issue.record("expected a linear dimension")
                return
            }
            #expect(isClose(from, want.0) && isClose(to, want.1) && isClose(side, want.2))
            #expect(isClose(direction, (to - from) * (1 / (to - from).length)))
        }
    }

    @Test func aCylinderShowsItsRadiusAsADiameter() async throws {
        var h = Harness()
        let cylinder = h.add(ImplicitCylinderNode.self, ["radius": .number(5), "height": .number(20)])
        let specs = try #require(try await h.run([cylinder]).results[cylinder.id]?.dimensions)
        let (diameter, height) = (try #require(specs.first { $0.target == .input("radius") }),
                                  try #require(specs.first { $0.target == .input("height") }))
        #expect(specs.count == 2)
        #expect(diameter.value == 10 && diameter.quantity == .diameter && diameter.inputScale == 0.5)
        #expect(height.value == 20 && height.quantity == .length && height.inputScale == 1)
        guard case let .radial(center, radius, normal, toward, _) = diameter.geometry,
              case let .linear(from, to, _, side, _) = height.geometry else {
            Issue.record("unexpected geometry")
            return
        }
        #expect(isClose(center, Vector3(0, 0, 10)) && isClose(radius, 5) && isClose(normal, .unitZ) && isClose(toward, .unitX))
        #expect(isClose(from, Vector3(5, 0, -10)) && isClose(to, Vector3(5, 0, 10)) && isClose(side, .unitX))
    }

    @Test func aSphereShowsItsDiameter() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let specs = try #require(try await h.run([sphere]).results[sphere.id]?.dimensions)
        let spec = try #require(specs.first)
        #expect(specs.count == 1 && spec.value == 20 && spec.inputScale == 0.5 && spec.quantity == .diameter)
        guard case let .radial(center, radius, normal, toward, _) = spec.geometry else {
            Issue.record("expected a radial dimension")
            return
        }
        #expect(isClose(center, .zero) && isClose(radius, 10) && isClose(normal, .unitZ))
        #expect(isClose(toward, Vector3(1, 1, 0) * (1 / 2.0.squareRoot())))
    }

    @Test func aShellDimensionsAConstantThicknessOnly() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 20, 20))])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(2)])
        h.wire(box, "implicit", to: shell, "implicit")
        let specs = try #require(try await h.run([shell]).results[shell.id]?.dimensions)
        let spec = try #require(specs.first)
        #expect(specs.count == 1 && spec.target == .input("thickness") && spec.value == 2 && spec.quantity == .length)
        guard case let .linear(from, to, direction, side, _) = spec.geometry else {
            Issue.record("expected a linear dimension")
            return
        }
        #expect(isClose(from, Vector3(10, 0, 10)) && isClose(to, Vector3(8, 0, 10)))
        #expect(isClose(direction, -.unitX) && isClose(side, .unitZ))

        let outward = h.add(ImplicitShellNode.self, ["thickness": .number(2), "side": .integer(1)])
        let centred = h.add(ImplicitShellNode.self, ["thickness": .number(2), "side": .integer(2)])
        h.wire(box, "implicit", to: outward, "implicit")
        h.wire(box, "implicit", to: centred, "implicit")
        let report = try await h.run([outward, centred])
        guard case let .linear(oFrom, oTo, _, _, _) = try #require(report.results[outward.id]?.dimensions.first).geometry,
              case let .linear(cFrom, cTo, _, _, _) = try #require(report.results[centred.id]?.dimensions.first).geometry else {
            Issue.record("expected linear dimensions")
            return
        }
        #expect(isClose(oFrom, Vector3(10, 0, 10)) && isClose(oTo, Vector3(12, 0, 10)))
        #expect(isClose(cFrom, Vector3(9, 0, 10)) && isClose(cTo, Vector3(11, 0, 10)))

        let gradient = h.add(LinearGradientNode.self)
        let graded = h.add(ImplicitShellNode.self)
        h.wire(box, "implicit", to: graded, "implicit")
        h.wire(gradient, "field", to: graded, "thickness")
        #expect(try await h.run([graded]).results[graded.id]?.dimensions.isEmpty ?? true)
    }
}
