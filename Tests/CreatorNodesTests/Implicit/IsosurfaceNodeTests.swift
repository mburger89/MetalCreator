import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Isosurface (implicit spec §3.1).
struct IsosurfaceNodeTests {
    static let help = "Wire a solid, an implicit solid or two corner points into “bounds” to say where to fill."

    /// A radial gradient of radius 20 about the origin: |p| / 20.
    func radial(_ h: inout Harness, radius: Double = 20) -> Node { h.add(RadialGradientNode.self, ["radius": .number(radius)]) }

    /// An isosurface of `radial` at level 0.5 with max slope 0.05, which is a ball of radius 10.
    func isosurface(_ h: inout Harness, radius: Double = 20, slope: Double = 0.05) -> Node {
        let iso = h.add(IsosurfaceNode.self, ["level": .number(0.5), "max slope": .number(slope)])
        h.wire(radial(&h, radius: radius), "field", to: iso, "field")
        return iso
    }

    /// Two vectors, (low, low, low) and (high, high, high), as one list.
    func corners(_ h: inout Harness, _ low: Double, _ high: Double) -> Node {
        let series = h.add(SeriesNode.self, ["start": .number(low), "step": .number(high - low), "count": .integer(2)])
        let vectors = h.add(VectorNode.self)
        for axis in ["x", "y", "z"] { h.wire(series, "values", to: vectors, SocketName(axis)) }
        return vectors
    }

    @Test func aFieldBelowALevelIsASolid() async throws {
        var h = Harness()
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let iso = isosurface(&h)
        h.wire(cube, "implicit", to: iso, "bounds")
        let report = try await h.run([iso])
        let solid = try #require(report.implicitSolid(iso))
        // |p| / 20 < 0.5 is a ball of radius 10, and (|p| / 20 − 0.5) ÷ 0.05 is |p| − 10.
        #expect(abs(solid.distance(0, 0, 0) + 10) < 1e-9 && abs(solid.distance(10, 0, 0)) < 1e-9)
        #expect(abs(solid.distance(14, 0, 0) - 4) < 1e-9)
        #expect(solid.lipschitz == 1)
        #expect(solid.description == "isosurface(radial(radius 20), level 0.5, max slope 0.05)")
        #expect(report.isOK(iso))
    }

    @Test func twoCornersNameTheRegion() async throws {
        var h = Harness()
        let iso = isosurface(&h)
        h.wire(corners(&h, -15, 15), "vector", to: iso, "bounds")
        let solid = try #require(try await h.run([iso]).implicitSolid(iso))
        #expect(solid.bounds == BoundingBox(min: Vector3(-15, -15, -15), max: Vector3(15, 15, 15)))
    }

    @Test func theRegionClipsTheSolid() async throws {
        var h = Harness()
        let iso = isosurface(&h)
        h.wire(corners(&h, 0, 12), "vector", to: iso, "bounds")
        let solid = try #require(try await h.run([iso]).implicitSolid(iso))
        #expect(solid.distance(5, 5, 5) < 0, "inside the ball and the region")
        #expect(solid.distance(-5, 5, 5) == 5, "inside the ball but 5 mm outside the region: the region's distance wins")
        #expect(solid.distance(14, 14, 14) > 0)
    }

    @Test func aSolidsBoxNamesTheRegionToo() async throws {
        var h = Harness()
        let iso = isosurface(&h)
        h.wire(h.box(30, 30, 30), "solid", to: iso, "bounds")
        let solid = try #require(try await h.run([iso]).implicitSolid(iso))
        #expect(solid.bounds == BoundingBox(min: Vector3(-15, -15, 0), max: Vector3(15, 15, 30)))
    }

    @Test func anImplicitSolidReadAsAFieldNeedsNoBounds() async throws {
        var h = Harness()
        let ball = h.add(ImplicitSphereNode.self)
        let iso = h.add(IsosurfaceNode.self, ["level": .number(3)])
        h.wire(ball, "implicit", to: iso, "field")
        let report = try await h.run([iso])
        let solid = try #require(report.implicitSolid(iso), "\(String(describing: report.state(iso)))")
        // Inside where the distance to the ball is below 3: a ball of radius 13, in a region 3 mm wider than the ball's box.
        #expect(solid.description == "isosurface(implicit(sphere(radius 10 mm)), level 3, max slope 1)")
        #expect(abs(solid.distance(13, 0, 0)) < 1e-9 && solid.bounds.max.x == 13)
        #expect(report.isOK(iso))
    }

    @Test func aDistanceToASolidIsBakedOverTheRegion() async throws {
        var h = Harness()
        let part = h.box(10, 10, 10)
        let distance = h.add(DistanceFieldNode.self)
        let iso = h.add(IsosurfaceNode.self, ["level": .number(2)])
        h.wire(part, "solid", to: distance, "target")
        h.wire(distance, "field", to: iso, "field")
        h.wire(h.box(30, 30, 30), "solid", to: iso, "bounds")
        let report = try await h.run([iso])
        let solid = try #require(report.implicitSolid(iso), "\(String(describing: report.state(iso)))")
        guard case .isosurface(let grading, _, _, _) = solid else { Issue.record("not an isosurface"); return }
        #expect(grading.baked.count == 1)
        // The signed distance below 2 is the part grown by 2 mm: 7 mm out from the middle along x, the grid being a little coarse.
        #expect(abs(solid.distance(7, 0, 5)) < 0.2)
    }

    @Test func aRegionIsRequiredAndMustHaveVolume() async throws {
        var h = Harness()
        let missing = isosurface(&h)
        let flat = isosurface(&h)
        h.wire(corners(&h, 3, 3), "vector", to: flat, "bounds")
        let wrong = isosurface(&h)
        h.wire(h.add(NumberNode.self), "value", to: wrong, "bounds")
        let report = try await h.run([missing, flat, wrong])
        #expect(report.error(missing) == "Isosurface needs a region to fill. \(Self.help)")
        #expect(report.error(flat) == "The region to fill has no volume. \(Self.help)")
        #expect(report.error(wrong) == "“bounds” takes a solid, an implicit solid or two points. \(Self.help)")
    }

    @Test func aMaxSlopeOfZeroOrLessIsRefused() async throws {
        var h = Harness()
        let iso = isosurface(&h, slope: 0)
        h.wire(corners(&h, -15, 15), "vector", to: iso, "bounds")
        #expect(try await h.run([iso]).error(iso) == "“max slope” must be greater than 0.")
    }

    @Test func aMaxSlopeSmallerThanTheFieldChangesWarnsOfHoles() async throws {
        var h = Harness()
        let iso = isosurface(&h, radius: 5, slope: 0.05)
        h.wire(corners(&h, -15, 15), "vector", to: iso, "bounds")
        let report = try await h.run([iso])
        #expect(report.warning(iso) == "The field can change by 0.2 per mm, more than “max slope” (0.05); the preview may have holes.")
        let solid = try #require(report.implicitSolid(iso))
        #expect(solid.lipschitz == 4, "the honest bound is the field's slope over the max slope: 0.2 ÷ 0.05")
    }
}
