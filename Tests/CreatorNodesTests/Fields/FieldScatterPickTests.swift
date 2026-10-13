import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Fields spec D7 and §8 (Paths): a pick on a scattered instance follows its number, and when the field, region or seed
/// renumbers the points so that the number no longer exists, it warns "Instance {n} no longer exists".
struct FieldScatterPickTests {
    /// A 60 × 40 profile at z = 0, scattered at spacing 6, Ø3 holes through the plate at the points, and an Edges by Tag.
    struct Fixture {
        var plate = PatternPlate()
        let scatter: Node, holes: Node, rule: Node

        init() {
            let region = plate.h.add(RectangleNode.self, ["width": .number(60), "height": .number(40), "plane": .plane(.xy)])
            scatter = plate.h.add(FieldScatterNode.self, ["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(3), "depth": .number(6)])
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(region, "profile", to: scatter, "profile")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(scatter, "placements", to: holes, "placements")
            plate.h.wire(holes, "solid", to: rule, "solid")
        }

        func bore(_ index: Int) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
        }

        func rim(of index: Int, in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(index)) } && sides.contains { $0.tags.contains(top) }
            }
        }
    }

    @Test func aPickOnTheLastScatteredPointWarnsOnceFewerPointsExist() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        let count = try #require(report.value(f.scatter, "placements")?.items.count)
        #expect(count > 20)
        let last = count - 1
        let solid = try onlySolid(report, f.holes)
        let edge = try #require(f.rim(of: last, in: solid))
        f.plate.h.set(f.rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: [edge.id])))
        let before = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(before.isOK(f.rule), "the pick resolves while its instance exists: \(String(describing: before.state(f.rule)))")

        f.plate.h.set(f.scatter, "minSpacing", .number(12))
        f.plate.h.set(f.scatter, "maxSpacing", .number(12))
        let after = try await f.plate.h.run([f.rule], kernel: kernel)
        let fewer = try #require(after.value(f.scatter, "placements")?.items.count)
        #expect(fewer < count)
        #expect(after.warning(f.rule) == "Instance {\(last)} no longer exists, so the edge picked on it isn't selected.")
    }
}
