import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Shell and Offset (implicit spec §3.3).
struct ImplicitShellOffsetNodeTests {
    func sphere(_ h: inout Harness, radius: Double = 10) -> Node {
        h.add(ImplicitSphereNode.self, ["radius": .number(radius)])
    }

    @Test func aShellIsAnInwardWallByDefault() async throws {
        var h = Harness()
        let shell = h.add(ImplicitShellNode.self)
        h.wire(sphere(&h), "implicit", to: shell, "implicit")
        let report = try await h.run([shell])
        let solid = try #require(report.implicitSolid(shell))
        #expect(solid.description == "shell(sphere(radius 10 mm), inward 2 mm)")
        #expect(solid.distance(10, 0, 0) == 0 && solid.distance(8, 0, 0) == 0 && solid.distance(9, 0, 0) == -1)
        #expect(solid.distance(0, 0, 0) == 8)
        #expect(report.isOK(shell))
    }

    @Test(arguments: [(1, "outward", 12.0, 10.0), (2, "centred", 11.0, 9.0)])
    func theSideChoosesWhereTheWallLies(_ side: Int, _ name: String, _ outer: Double, _ inner: Double) async throws {
        var h = Harness()
        let shell = h.add(ImplicitShellNode.self, ["side": .integer(side)])
        h.wire(sphere(&h), "implicit", to: shell, "implicit")
        let solid = try #require(try await h.run([shell]).implicitSolid(shell))
        #expect(solid.description == "shell(sphere(radius 10 mm), \(name) 2 mm)")
        #expect(solid.distance(outer, 0, 0) == 0 && solid.distance(inner, 0, 0) == 0)
    }

    @Test func anUnknownSideIsRefused() async throws {
        var h = Harness()
        let shell = h.add(ImplicitShellNode.self, ["side": .integer(7)])
        h.wire(sphere(&h), "implicit", to: shell, "implicit")
        #expect(try await h.run([shell]).error(shell) == "Choose Inward, Outward, or Centred for “side”.")
    }

    @Test func aFieldGradesTheThickness() async throws {
        var h = Harness()
        let gradient = h.add(LinearGradientNode.self, ["length": .number(20)])
        let shell = h.add(ImplicitShellNode.self)
        h.wire(sphere(&h), "implicit", to: shell, "implicit")
        h.wire(gradient, "field", to: shell, "thickness")
        let report = try await h.run([shell])
        let solid = try #require(report.implicitSolid(shell))
        // z / 20 is 0 on the XY plane and 0.5 at z = 10: no wall in the lower half, 0.5 mm at the top.
        #expect(solid.lipschitz == 1.05)
        // At z = 9.75 the thickness is 9.75 / 20 and the sphere's surface is 0.25 mm above.
        let thickness = 9.75 / 20
        #expect(abs(solid.distance(0, 0, 9.75) - (abs(-0.25 + thickness / 2) - thickness / 2)) < 1e-12)
        #expect(solid.distance(0, 0, -5) == 5, "no wall where the thickness is 0 or less: the value is the distance to the surface")
        #expect(report.warning(shell) == "“thickness” is below 0 in places; it is held at 0 there.")
    }

    @Test func aThicknessWithoutAKnownSlopeWarnsThatThePreviewMayBeSlow() async throws {
        var h = Harness()
        let kernel = FakeKernel()
        let box = h.box(10, 10, 10)
        let distance = h.add(DistanceFieldNode.self)
        let product = h.add(FieldMultiplyNode.self)
        let shell = h.add(ImplicitShellNode.self)
        h.wire(box, "solid", to: distance, "target")
        h.wire(distance, "field", to: product, "a")
        h.wire(distance, "field", to: product, "b")
        h.wire(product, "field", to: shell, "thickness")
        h.wire(sphere(&h), "implicit", to: shell, "implicit")
        let report = try await h.run([shell], kernel: kernel)
        let solid = try #require(report.implicitSolid(shell))
        #expect(report.warning(shell)?.contains("“thickness” changes at a rate that isn't known, so the preview may be slow.") == true)
        #expect(solid.lipschitz >= 1 + Field.unknownSlope)
    }

    @Test func anOffsetMovesTheSurface() async throws {
        var h = Harness()
        let grow = h.add(ImplicitOffsetNode.self)
        let shrink = h.add(ImplicitOffsetNode.self, ["distance": .number(-3)])
        let ball = sphere(&h)
        h.wire(ball, "implicit", to: grow, "implicit")
        h.wire(ball, "implicit", to: shrink, "implicit")
        let report = try await h.run([grow, shrink])
        let (big, small) = (try #require(report.implicitSolid(grow)), try #require(report.implicitSolid(shrink)))
        #expect(big.description == "offset(sphere(radius 10 mm), 1 mm)" && big.distance(11, 0, 0) == 0)
        #expect(small.description == "offset(sphere(radius 10 mm), −3 mm)" && small.distance(7, 0, 0) == 0)
        #expect(report.isOK(grow) && report.isOK(shrink), "a negative offset is no warning")
    }

    @Test func wavesInAnOffsetFollowTheField() async throws {
        var h = Harness()
        let noise = h.add(NoiseFieldNode.self, ["scale": .number(5)])
        let offset = h.add(ImplicitOffsetNode.self)
        h.wire(sphere(&h), "implicit", to: offset, "implicit")
        h.wire(noise, "field", to: offset, "distance")
        let report = try await h.run([offset])
        let solid = try #require(report.implicitSolid(offset))
        #expect(report.isOK(offset))
        // The noise is in 0…1, so the surface moved out by up to a millimetre.
        #expect(solid.bounds.max.x == 11 && solid.lipschitz > 1)
    }

    @Test func aShellAndAnOffsetNeedAnImplicit() async throws {
        var h = Harness()
        let shell = h.add(ImplicitShellNode.self)
        let offset = h.add(ImplicitOffsetNode.self)
        let report = try await h.run([shell, offset])
        guard case .idle(let reason?)? = report.state(shell) else { Issue.record("expected idle"); return }
        #expect(reason == "Connect or set “implicit”.")
        guard case .idle? = report.state(offset) else { Issue.record("expected idle"); return }
    }

    @Test func aWallThickerThanABakedSolidsBandWarns() {
        let size = DistanceBlocks.blockSize
        let blocks = DistanceBlocks(origin: .zero, spacing: 1, blockCounts: [1, 1, 1], table: [0],
                                    pool: [Float](repeating: 1, count: size * size * size), coarse: [0], band: 3)
        let baked = ImplicitSolid.baked(blocks, label: "Part")
        #expect(ImplicitReach.warnings(for: baked, reachedBy: 2).isEmpty)
        #expect(ImplicitReach.warnings(for: baked, reachedBy: 5)
            == ["The distance reaches 5 mm from the surface, past the 3 mm To Implicit measured exactly, so it may be inaccurate."])
        #expect(ImplicitReach.warnings(for: .sphere(radius: 3), reachedBy: 500).isEmpty, "an analytic solid is exact everywhere")
    }
}
