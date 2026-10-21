#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// The Face mapping of the lattice nodes on curved faces of real OpenCascade solids (implicit spec §3.5, §7): a cylinder's side and a
/// fillet. The cells must follow the face (wrap evenly round the cylinder), the axis the map is singular on is left solid with the
/// spec's warning, and a face of another solid is refused.
struct FaceMappingOCCTTests {
    /// A cylinder of `diameter` and `height` (a circle extruded) → To Implicit → a gyroid of `cell` mm set to Face mapping.
    struct Rig {
        var builder = GraphBuilder()
        var extrude: Node
        var lattice: Node
        var kernel = OCCTKernel()
    }

    func cylinder(diameter: Double = 20, height: Double = 20, cell: Double = 8) -> Rig {
        var builder = GraphBuilder()
        let circle = builder.add(CircleNode.self, ["diameter": .number(diameter)])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(height)])
        builder.wire(circle, "profile", to: extrude, "profile")
        return rig(builder, extrude, cell: cell)
    }

    /// A 40 × 40 × 10 block with its four vertical edges filleted at `radius`.
    func filleted(radius: Double = 4, cell: Double = 8) -> Rig {
        var builder = GraphBuilder()
        let (rectangle, extrude) = builder.solid(distance: 10)
        builder.graph.nodes[rectangle.id]?.inputValues["width"] = .number(40)
        builder.graph.nodes[rectangle.id]?.inputValues["height"] = .number(40)
        let edges = builder.add(EdgesByDirectionNode.self, ["direction": .vector(.unitZ)])
        let fillet = builder.add(FilletNode.self, ["radius": .number(radius)])
        builder.wire(extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        return rig(builder, fillet, cell: cell)
    }

    func rig(_ start: GraphBuilder, _ solid: Node, cell: Double) -> Rig {
        var builder = start
        let implicit = builder.add(ToImplicitNode.self, ["tolerance": .number(0.02)])
        let lattice = builder.add(TPMSNode.self, ["cell size": .number(cell), "mapping": .integer(3)])
        builder.wire(solid, "solid", to: implicit, "solid")
        builder.wire(implicit, "implicit", to: lattice, "region")
        return Rig(builder: builder, extrude: solid, lattice: lattice)
    }

    func run(_ rig: Rig) async throws -> EvaluationReport {
        try await Evaluator(registry: BuiltInNodes.registry, kernel: rig.kernel).evaluate(rig.builder.graph, demand: [rig.lattice.id])
    }

    func solid(_ rig: Rig) async throws -> Solid {
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: rig.kernel)
            .evaluate(rig.builder.graph, demand: [rig.extrude.id])
        let items = try #require(report.results[rig.extrude.id]?.outputs?["solid"]?.items)
        return try #require(items.compactMap { item -> Solid? in if case .solid(let solid) = item { solid } else { nil } }.first)
    }

    func pick(_ face: FaceInfo, of solid: Solid) throws -> ConstantValue {
        .facePick(try #require(solid.topology.facePick(for: face.id)))
    }

    func lattice(_ report: EvaluationReport, _ node: Node) throws -> TPMSLattice {
        let solid = try #require(report.results[node.id]?.outputs?["implicit"]?.items.compactMap { item -> ImplicitSolid? in
            if case .implicit(let reference) = item { reference.solid } else { nil }
        }.first)
        guard case .tpms(let lattice)? = firstLattice(solid) else { throw NodeError.invalidValue("no gyroid in \(solid.description)") }
        return lattice
    }

    func firstLattice(_ solid: ImplicitSolid) -> ImplicitSolid? {
        if case .tpms = solid { return solid }
        return solid.children.lazy.compactMap(firstLattice).first
    }

    // MARK: A cylinder's side

    @Test func theCellsWrapEvenlyRoundACylindersSideAndTheAxisIsLeftSolidWithTheSpecsWarning() async throws {
        var rig = cylinder()
        let part = try await solid(rig)
        let side = try #require(part.topology.faces.first { $0.kind == .cylinder })
        rig.builder.graph.nodes[rig.lattice.id]?.inputValues[NodeSetting.face] = try pick(side, of: part)
        let report = try await run(rig)
        #expect(report.results[rig.lattice.id]?.state != nil)
        guard case .warning(let message)? = report.results[rig.lattice.id]?.state else {
            Issue.record("no warning: \(String(describing: report.results[rig.lattice.id]?.state))")
            return
        }
        #expect(message.contains("The mapping is singular near the cylinder's axis; cells there are left solid."), "\(message)")
        let gyroid = try lattice(report, rig.lattice)
        guard case .face(let map) = gyroid.mapping, let radius = map.firstRadius else { Issue.record("not face mapped"); return }
        let solid = ImplicitSolid.tpms(gyroid)
        // A whole number of cells goes round: the lattice at one cell's angle further round is the same.
        let cells = 2 * Double.pi * radius / 8
        #expect(abs(cells - cells.rounded()) < 1e-9 && cells >= 1, "\(cells) cells go round")
        let step = 2 * Double.pi / cells.rounded()
        for (reach, z) in [(7.0, 5.0), (8.5, 12.0), (9.2, 17.0)] {
            for start in [0.4, 2.0, 4.5] {
                let a = Vector3(reach * cos(start), reach * sin(start), z)
                let b = Vector3(reach * cos(start + step), reach * sin(start + step), z)
                #expect(abs(solid.signedDistance(at: a) - solid.signedDistance(at: b)) < 0.03, "ring \(reach) at \(start)")
            }
        }
        // The axis, and within a millimetre of it, is solid.
        for z in stride(from: 3.0, through: 17.0, by: 2.0) { #expect(solid.signedDistance(at: Vector3(0.4, 0, z)) <= 1e-9) }
    }

    @Test func theMappedCoordinatesAreTheSurfacesNotThePlanes() async throws {
        var rig = cylinder()
        let part = try await solid(rig)
        let side = try #require(part.topology.faces.first { $0.kind == .cylinder })
        rig.builder.graph.nodes[rig.lattice.id]?.inputValues[NodeSetting.face] = try pick(side, of: part)
        let gyroid = try lattice(try await run(rig), rig.lattice)
        // The depth is the distance from the surface along its normal: 3 mm in from the side of a 10 mm radius, and 2 mm out.
        let inside = gyroid.mapping.coordinates(at: Vector3(7, 0, 10)), outside = gyroid.mapping.coordinates(at: Vector3(0, 12, 10))
        #expect(abs(inside.z + 3) < 0.05 && abs(outside.z - 2) < 0.05, "\(inside.z) and \(outside.z)")
        // Height along the axis is millimetres (its direction is the face's own, which may run downwards).
        let higher = gyroid.mapping.coordinates(at: Vector3(7, 0, 14))
        #expect(abs(abs(higher.y - inside.y) - 4) < 0.02, "\(higher.y - inside.y)")
    }

    // MARK: A fillet

    @Test func aFilletIsAPartialSurfaceWhoseCellsFollowItsCurve() async throws {
        var rig = filleted(radius: 4)
        let part = try await solid(rig)
        let blends = part.topology.faces.filter { $0.kind == .cylinder }
        #expect(blends.count == 4)
        let blend = try #require(blends.first)
        rig.builder.graph.nodes[rig.lattice.id]?.inputValues[NodeSetting.face] = try pick(blend, of: part)
        let report = try await run(rig)
        #expect(report.results[rig.lattice.id]?.state != nil)
        if case .error(let message)? = report.results[rig.lattice.id]?.state { Issue.record("\(message)") }
        let gyroid = try lattice(report, rig.lattice)
        guard case .face(let map) = gyroid.mapping else { Issue.record("not face mapped"); return }
        #expect(map.chart.kind == .cylinder && map.chart.firstTurn == nil, "a fillet is part of a cylinder, with no period")
        // The fillet's axis is 4 mm in from both sides of its corner. Towards the corner from the axis the depth is the distance from
        // the axis less 4: -2 two millimetres out, and 4 (√2 - 1) at the old corner. (At the axis itself every point of the arc is as
        // near, which is what makes it singular.)
        let sign = (x: blend.centroid.x > 0 ? 1.0 : -1.0, y: blend.centroid.y > 0 ? 1.0 : -1.0)
        let corner = Vector3(20 * sign.x, 20 * sign.y, 5)
        let axis = Vector3(16 * sign.x, 16 * sign.y, 5)
        let toward = Vector3(sign.x, sign.y, 0) * (1 / 2.0.squareRoot())
        #expect(abs(map.coordinates(at: axis + toward * 2).z + 2) < 0.15, "\(map.coordinates(at: axis + toward * 2))")
        #expect(abs(map.coordinates(at: corner).z - 4 * (2.0.squareRoot() - 1)) < 0.15, "\(map.coordinates(at: corner))")
    }

    // MARK: A face of another solid

    @Test func aFaceOfAnotherSolidIsRefusedByName() async throws {
        var rig = cylinder()
        let other = cylinder(diameter: 30)
        let foreign = try await solid(other)
        let side = try #require(foreign.topology.faces.first { $0.kind == .cylinder })
        rig.builder.graph.nodes[rig.lattice.id]?.inputValues[NodeSetting.face] = try pick(side, of: foreign)
        let report = try await run(rig)
        guard case .error(let message)? = report.results[rig.lattice.id]?.state else {
            Issue.record("no error: \(String(describing: report.results[rig.lattice.id]?.state))")
            return
        }
        #expect(message.contains("isn't on the solid this region came from"), "\(message)")
    }
}
#endif
