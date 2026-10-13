import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Linear Gradient, Radial Gradient and Noise Field (fields spec §3.1).
struct GradientAndNoiseNodeTests {
    // MARK: Linear Gradient

    @Test func aLinearGradientIsZeroOnThePlaneAndOneALengthAlongTheNormal() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["offset": .number(2)])
        let gradient = h.add(LinearGradientNode.self, ["length": .number(5)])
        h.wire(plane, "plane", to: gradient, "plane")
        let report = try await h.run([gradient])
        #expect(report.field(gradient)?.description == "linear(length 5)")
        let points = [Vector3(9, 9, 2), Vector3(0, 0, 7), Vector3(0, 0, -3), Vector3(1, 1, 12)]
        let found = try await sampled(report.field(gradient), at: points)
        #expect(found == [0, 1, -1, 2], "unclamped, either side")
    }

    @Test func theDefaultLinearGradientIsTenMillimetresAlongZ() async throws {
        var h = Harness()
        let gradient = h.add(LinearGradientNode.self)
        let report = try await h.run([gradient])
        #expect(try await sampled(report.field(gradient), at: [Vector3(0, 0, 10), Vector3(0, 0, 5)]) == [1, 0.5])
    }

    @Test func aLinearGradientRefusesAnEmptyLengthOrAPlaneWithoutADirection() async throws {
        var h = Harness()
        let flat = h.add(LinearGradientNode.self, ["length": .number(0)])
        let negative = h.add(LinearGradientNode.self, ["length": .number(-2)])
        let blind = h.add(LinearGradientNode.self, ["plane": .plane(Plane(origin: .zero, normal: .zero, xAxis: .unitX))])
        let report = try await h.run([flat, negative, blind])
        #expect(report.error(flat) == "“length” must be greater than 0 mm.")
        #expect(report.error(negative) == "“length” must be greater than 0 mm.")
        #expect(report.error(blind) == "“plane” has no direction.")
    }

    // MARK: Radial Gradient

    @Test func aRadialGradientIsZeroAtTheCentreAndOneAtTheRadius() async throws {
        var h = Harness()
        let centre = h.add(VectorNode.self, ["x": .number(1), "y": .number(1), "z": .number(1)])
        let gradient = h.add(RadialGradientNode.self, ["radius": .number(2)])
        h.wire(centre, "vector", to: gradient, "center")
        let report = try await h.run([gradient])
        #expect(report.field(gradient)?.description == "radial(radius 2)")
        #expect(try await sampled(report.field(gradient), at: [Vector3(1, 1, 1), Vector3(1, 1, 3), Vector3(1, 1, -3)]) == [0, 1, 2])
    }

    @Test func aRadialGradientRefusesAnEmptyRadius() async throws {
        var h = Harness()
        let zero = h.add(RadialGradientNode.self, ["radius": .number(0)])
        let report = try await h.run([zero])
        #expect(report.error(zero) == "“radius” must be greater than 0 mm.")
    }

    // MARK: Noise Field

    @Test func theNoiseFieldHasTheSeedsNoise() async throws {
        var h = Harness()
        let noise = h.add(NoiseFieldNode.self, ["seed": .integer(42), "scale": .number(10), "octaves": .integer(1)])
        let report = try await h.run([noise])
        #expect(report.field(noise)?.description == "noise(seed 42, scale 10, octaves 1)")
        let points = [Vector3(1, 2, 3), Vector3(-4.5, 0.25, 7), Vector3(10, 10, 10)]
        let expected = FieldNoise(seed: 42, scale: 10, octaves: 1)
        #expect(try await sampled(report.field(noise), at: points) == points.map { expected.value(at: $0) })
    }

    @Test func theSameSeedIsTheSameFieldAndAnotherSeedIsAnother() async throws {
        var h = Harness()
        let a = h.add(NoiseFieldNode.self, ["seed": .integer(5)]), again = h.add(NoiseFieldNode.self, ["seed": .integer(5)])
        let other = h.add(NoiseFieldNode.self, ["seed": .integer(6)])
        let report = try await h.run([a, again, other])
        let points = (0..<20).map { Vector3(Double($0) * 1.3 + 0.1, Double($0) * 0.7, 2.2) }
        let first = try await sampled(report.field(a), at: points)
        #expect(first == (try await sampled(report.field(again), at: points)))
        #expect(first != (try await sampled(report.field(other), at: points)))
    }

    @Test func theNoiseFieldRefusesAnEmptyScaleAndOctavesOutsideOneToSix() async throws {
        var h = Harness()
        let flat = h.add(NoiseFieldNode.self, ["scale": .number(0)])
        let none = h.add(NoiseFieldNode.self, ["octaves": .integer(0)])
        let many = h.add(NoiseFieldNode.self, ["octaves": .integer(7)])
        let six = h.add(NoiseFieldNode.self, ["octaves": .integer(6)])
        let report = try await h.run([flat, none, many, six])
        #expect(report.error(flat) == "“scale” must be greater than 0 mm.")
        #expect(report.error(none) == "“octaves” must be from 1 to 6.")
        #expect(report.error(many) == "“octaves” must be from 1 to 6.")
        #expect(report.isOK(six))
    }
}
