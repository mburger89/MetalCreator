import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The Face mapping of the lattice nodes (implicit spec §3.5) on the Fake kernel's planar faces: the pick found among the solids the
/// region came from, the errors for a pick that is not on one, the chart measured once, and the warnings. A curved face of a real
/// OpenCascade solid is in `FaceMappingOCCTTests`.
struct LatticeFaceMappingNodeTests {
    /// A 20 × 20 × 10 block → To Implicit → a lattice of `definition` set to Face mapping, with `pick` (or none) as the face. Returns the
    /// extrude (to read the block's faces from), the lattice, and the harness.
    struct Rig {
        var h = Harness()
        var block: Node
        var lattice: Node
        var other: Node
    }

    /// - Parameter moved: the region is the baked block moved 30 mm along the plane's normal by Place.
    func rig(_ definition: any NodeDefinition.Type = TPMSNode.self, _ settings: [SocketName: ConstantValue] = [:],
             moved: Bool = false) -> Rig {
        var h = Harness()
        let block = h.box(20, 20, 10)
        let other = h.box(30, 30, 30)
        let implicit = h.add(ToImplicitNode.self, ["tolerance": .number(0.05)])
        h.wire(block, "solid", to: implicit, "solid")
        let lattice = h.add(definition, ["mapping": .integer(3), "cell size": .number(6), "count": .integer(30)]
            .merging(settings) { _, given in given })
        if moved {
            let placed = h.add(PlaceNode.self)
            let plane = h.add(PlaneNode.self, ["offset": .number(30)])
            h.wire(implicit, "implicit", to: placed, "implicit")
            h.wire(plane, "plane", to: placed, "placements")
            h.wire(placed, "implicits", to: lattice, "region")
        } else {
            h.wire(implicit, "implicit", to: lattice, "region")
        }
        return Rig(h: h, block: block, lattice: lattice, other: other)
    }

    /// The pick of the block's top face (looking up).
    func topPick(_ rig: Rig, of extrude: Node? = nil) async throws -> FacePick {
        let report = try await rig.h.run([extrude ?? rig.block])
        let solid = try onlySolid(report, extrude ?? rig.block)
        let top = try #require(solid.topology.faces.first { $0.normal == .unitZ })
        return try #require(solid.topology.facePick(for: top.id))
    }

    /// The mapping of the lattice in a node's output.
    func mapping(of solid: ImplicitSolid) -> LatticeMapping? {
        switch solid.firstLattice {
        case .tpms(let lattice)?: lattice.mapping
        case .struts(let lattice)?: lattice.mapping
        case .voronoi(let lattice)?: lattice.mapping
        default: nil
        }
    }

    // MARK: A pick on the region's own solid

    @Test(arguments: LatticeMappingNodeTests.nodes.indices)
    func aPickOnTheRegionsSolidMapsTheCellsToItsFace(_ index: Int) async throws {
        let (definition, settings) = LatticeMappingNodeTests.nodes[index]
        var rig = rig(definition, settings)
        rig.h.set(rig.lattice, NodeSetting.face, .facePick(try await topPick(rig)))
        let report = try await rig.h.run([rig.lattice])
        #expect(report.error(rig.lattice) == nil, "\(String(describing: report.state(rig.lattice)))")
        let solid = try #require(report.implicitSolid(rig.lattice))
        guard case .face(let map)? = mapping(of: solid) else {
            Issue.record("not face mapped: \(solid.description)")
            return
        }
        #expect(solid.description.contains(", face") && map.chart.kind == .plane && !map.chart.hasSingular)
        #expect(report.isOK(rig.lattice), "a plane is not singular anywhere: \(String(describing: report.state(rig.lattice)))")
    }

    @Test func theFaceCoordinatesOfTheTopOfABlockAreMillimetresFromItsMiddle() async throws {
        var rig = rig()
        let pick = try await topPick(rig)
        rig.h.set(rig.lattice, NodeSetting.face, .facePick(pick))
        let solid = try #require(try await rig.h.run([rig.lattice]).implicitSolid(rig.lattice))
        guard case .face(let map)? = mapping(of: solid) else { Issue.record("not face mapped"); return }
        let top = pick.centroid ?? .zero
        let (here, there) = (map.coordinates(at: top + Vector3(3, 0, 1)), map.coordinates(at: top))
        // The Fake's frame takes u along X for a face that looks up, v along Y; the depth is along the normal.
        #expect(abs(here.x - there.x - 3) < 1e-3 && abs(here.y - there.y) < 1e-3, "\(here) against \(there)")
        #expect(abs(here.z - there.z - 1) < 1e-3, "one millimetre up the normal is one millimetre of depth")
    }

    // MARK: Refusals

    @Test func aFaceOfAnotherSolidIsRefused() async throws {
        var rig = rig()
        rig.h.set(rig.lattice, NodeSetting.face, .facePick(try await topPick(rig, of: rig.other)))
        let report = try await rig.h.run([rig.lattice])
        #expect(report.error(rig.lattice) == LatticeFaceMapping.wrongSolid)
    }

    @Test func noPickIsAskedFor() async throws {
        let rig = rig()
        #expect(try await rig.h.run([rig.lattice]).error(rig.lattice) == LatticeFaceMapping.nothingPicked)
    }

    @Test func aPickThatIsNotAFacePickIsRefused() async throws {
        var rig = rig()
        rig.h.set(rig.lattice, NodeSetting.face, .number(1))
        #expect(try await rig.h.run([rig.lattice]).error(rig.lattice) == LatticeFaceMapping.unreadablePick)
    }

    @Test func aRegionThatIsNotMadeFromASolidHasNoFace() async throws {
        var h = Harness()
        let ball = h.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let lattice = h.add(TPMSNode.self, ["mapping": .integer(3)])
        h.wire(ball, "implicit", to: lattice, "region")
        h.set(lattice, NodeSetting.face, .facePick(FacePick(tags: [TopoTag(NodeTag(node: NodeID(), item: 0), .unnamed(face: 0))])))
        #expect(try await h.run([lattice]).error(lattice) == LatticeFaceMapping.noSource)
    }

    @Test func aRegionMovedAwayFromItsSolidIsRefusedInWords() async throws {
        var rig = rig(moved: true)
        rig.h.set(rig.lattice, NodeSetting.face, .facePick(try await topPick(rig)))
        #expect(try await rig.h.run([rig.lattice]).error(rig.lattice) == LatticeFaceMapping.movedSource)
    }

    // MARK: Once per face and tolerance

    @Test func editingANumberDownstreamMeasuresNothingAgain() async throws {
        var rig = rig()
        rig.h.set(rig.lattice, NodeSetting.face, .facePick(try await topPick(rig)))
        // One evaluator keeps the block's solid between the two runs, as the app's does between edits.
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let first = try await evaluator.evaluate(rig.h.graph, demand: [rig.lattice.id])
        rig.h.set(rig.lattice, "thickness", .number(1.4))
        let second = try await evaluator.evaluate(rig.h.graph, demand: [rig.lattice.id])
        #expect(second.error(rig.lattice) == nil)
        guard case .face(let before)? = mapping(of: try #require(first.implicitSolid(rig.lattice))),
              case .face(let after)? = mapping(of: try #require(second.implicitSolid(rig.lattice))) else {
            Issue.record("not face mapped")
            return
        }
        #expect(before.chart === after.chart, "the chart of this face and tolerance is the one in the cache")
    }
}
