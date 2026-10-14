import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing
@testable import CreatorNodes

/// To Implicit (implicit spec §3.1, §4.4).
struct ToImplicitNodeTests {
    @Test func aSolidBecomesItsSignedDistance() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let toImplicit = h.add(ToImplicitNode.self, ["tolerance": .number(0.04)])
        h.wire(box, "solid", to: toImplicit, "solid")
        let report = try await h.run([toImplicit])
        let solid = try #require(report.implicitSolid(toImplicit))
        #expect(solid.description == "implicit(solid)")
        #expect(abs(solid.distance(0, 0, 0.5) + 0.5) < 0.01 && abs(solid.distance(8, 0, 5) - 3) < 0.01)
        #expect(report.isOK(toImplicit))
        #expect(solid.lipschitz >= 1 && solid.lipschitz < 2)
    }

    @Test func aNamedNodeNamesItsSolid() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let named = h.add(ToImplicitNode.self, ["tolerance": .number(0.04)])
        h.rename(named, "Bracket")
        h.wire(box, "solid", to: named, "solid")
        let solid = try #require(try await h.run([named]).implicitSolid(named))
        #expect(solid.description == "implicit(Bracket)")
    }

    @Test func theInspectorFactsAreTheBakeTimeAndMemory() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let toImplicit = h.add(ToImplicitNode.self, ["tolerance": .number(0.04)])
        h.wire(box, "solid", to: toImplicit, "solid")
        let solid = try #require(try await h.run([toImplicit]).implicitSolid(toImplicit))
        let facts = solid.inspectorFacts
        #expect(facts.map(\.label) == ["Bake time", "Bake memory"])
        #expect(facts[0].value.hasSuffix(" s") && !facts[1].value.isEmpty)
        #expect(ImplicitSolid.sphere(radius: 3).inspectorFacts.isEmpty)
    }

    @Test func aToleranceBelowTheMinimumIsRefused() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let toImplicit = h.add(ToImplicitNode.self, ["tolerance": .number(0.0005)])
        h.wire(box, "solid", to: toImplicit, "solid")
        #expect(try await h.run([toImplicit]).error(toImplicit) == "“tolerance” must be at least 0.001 mm.")
    }

#if canImport(CreatorOCCT)
    @Test func aFilletedPartIsMeasuredToTheKernelsTolerance() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(20, 20, 10)
        let edges = h.add(AllEdgesNode.self)
        let fillet = h.add(FilletNode.self, ["radius": .number(2)])
        let toImplicit = h.add(ToImplicitNode.self, ["tolerance": .number(0.04)])
        h.wire(box, "solid", to: edges, "solid")
        h.wire(edges, "edges", to: fillet, "edges")
        h.wire(fillet, "solid", to: toImplicit, "solid")
        let report = try await h.run([toImplicit], kernel: kernel)
        let solid = try #require(report.implicitSolid(toImplicit), "\(String(describing: report.state(toImplicit)))")
        // The part is a 20 × 20 × 10 box standing on z = 0, all twelve edges rounded by 2 mm: a rounded box.
        let reference = ImplicitSolid.moved(.box(halfSize: Vector3(10, 10, 5), cornerRadius: 2),
                                            RigidMove(origin: Vector3(0, 0, 5), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let random = SeededRandom(seed: 8, stream: 1)
        var near = 0.0, deep = 0.0
        var checked = 0
        for index in 0..<1500 {
            let point = Vector3(random.unit(at: 3 * index) * 30 - 15, random.unit(at: 3 * index + 1) * 30 - 15,
                                random.unit(at: 3 * index + 2) * 20 - 5)
            let exact = reference.signedDistance(at: point)
            guard abs(exact) < 3 else { continue }
            checked += 1
            let difference = abs(solid.signedDistance(at: point) - exact)
            // The tolerance asked for is 0.04 mm: the tessellation is off by that much, and a 0.8 mm grid across a 2 mm fillet by about as
            // much again. Deeper in, near the true distance's ridge, trilinear cuts the ridge short by a little more.
            if abs(exact) < 1.5 { near = max(near, difference) } else { deep = max(deep, difference) }
        }
        #expect(checked > 300)
        #expect(near < 0.2, "worst difference within 1.5 mm of the surface: \(near) mm")
        #expect(deep < 0.3, "worst difference 1.5 to 3 mm out or in: \(deep) mm")
    }
#endif
}
