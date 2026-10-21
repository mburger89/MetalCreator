import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The `mapping` setting of the three lattice nodes (implicit spec §3.5): its inputs and their defaults, what each mapping builds, the
/// warnings, the inspector showing only the active mapping's inputs, and files from before 7c-4 reading Straight.
struct LatticeMappingNodeTests {
    /// The three lattice nodes with settings that fill a 40 mm cube about the origin.
    static let nodes: [(definition: any NodeDefinition.Type, settings: [SocketName: ConstantValue])] = [
        (TPMSNode.self, ["cell size": .number(8), "thickness": .number(1)]),
        (StrutLatticeNode.self, ["cell size": .number(8), "strut radius": .number(0.6)]),
        (VoronoiLatticeNode.self, ["count": .integer(40), "thickness": .number(0.8)]),
    ]

    func lattice(_ h: inout Harness, _ index: Int, _ extra: [SocketName: ConstantValue] = [:]) -> Node {
        let (definition, settings) = Self.nodes[index]
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let node = h.add(definition, settings.merging(extra) { _, given in given })
        h.wire(box, "implicit", to: node, "region")
        return node
    }

    func solid(_ index: Int, _ extra: [SocketName: ConstantValue] = [:]) async throws -> ImplicitSolid {
        var h = Harness()
        let node = lattice(&h, index, extra)
        return try #require(try await h.run([node]).implicitSolid(node))
    }

    static let cylindrical: [SocketName: ConstantValue] = ["mapping": .integer(1)]
    static let spherical: [SocketName: ConstantValue] = ["mapping": .integer(2)]

    // MARK: Sockets

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func everyLatticeNodeHasTheMappingInputs(_ index: Int) throws {
        let definition = Self.nodes[index].definition
        let mapping = try #require(definition.inputs.first { $0.name == "mapping" })
        #expect(mapping.type == .integer && mapping.defaultValue == .integer(0))
        #expect(LatticeMappingKind.options == ["Straight", "Cylindrical", "Spherical", "Face"])
        let axis = try #require(definition.inputs.first { $0.name == "axis" })
        #expect(axis.type == .plane && axis.defaultValue == .plane(.xy))
        let centre = try #require(definition.inputs.first { $0.name == "centre" })
        #expect(centre.type == .vector && centre.defaultValue == .vector(.zero))
        #expect(definition.typeVersion == 2, "no version bump: a file without `mapping` reads the socket's default, Straight")
    }

    // MARK: Building

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func straightIsTheDefaultAndChangesNothing(_ index: Int) async throws {
        let plain = try await solid(index)
        let explicit = try await solid(index, ["mapping": .integer(0)])
        #expect(plain.description == explicit.description && !plain.description.contains("cylindrical"))
        let points = ImplicitSolidPropertyTestsPoints.points
        #expect(plain.signedDistances(at: points) == explicit.signedDistances(at: points))
    }

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func cylindricalWrapsTheCellsRoundTheAxis(_ index: Int) async throws {
        let straight = try await solid(index)
        let wrapped = try await solid(index, Self.cylindrical)
        #expect(wrapped.description.contains("cylindrical") && wrapped.description != straight.description)
        #expect(wrapped.bounds == straight.bounds, "the lattice still fills the region's box")
        #expect(wrapped.lipschitz > straight.lipschitz, "the stretch is in the bound")
        let points = ImplicitSolidPropertyTestsPoints.points
        let (a, b) = (straight.signedDistances(at: points), wrapped.signedDistances(at: points))
        #expect(zip(a, b).contains { abs($0 - $1) > 0.1 }, "a different pattern")
    }

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func sphericalWrapsTheCellsRoundTheCentre(_ index: Int) async throws {
        let wrapped = try await solid(index, Self.spherical)
        #expect(wrapped.description.contains("spherical"))
        let moved = try await solid(index, Self.spherical.merging(["centre": .vector(Vector3(3, 0, 0))]) { _, given in given })
        let points = ImplicitSolidPropertyTestsPoints.points
        let (a, b) = (wrapped.signedDistances(at: points), moved.signedDistances(at: points))
        #expect(zip(a, b).contains { abs($0 - $1) > 0.1 }, "the centre moves the pattern")
    }

    @Test func theAxisPlaneSetsTheAxisAndTheTurnIsWholeCells() async throws {
        let tilted = Plane(origin: Vector3(5, 0, 0), normal: .unitX, xAxis: .unitY)
        let wrapped = try await solid(0, Self.cylindrical.merging(["axis": .plane(tilted)]) { _, given in given })
        guard case .tpms(let lattice)? = wrapped.firstLattice, case .cylindrical(let map) = lattice.mapping else {
            Issue.record("not a cylindrical gyroid: \(wrapped.description)")
            return
        }
        #expect(map.origin == tilted.origin && map.axis == .unitX && map.reference == .unitY)
        let cells = map.turn / 8
        #expect(abs(cells - cells.rounded()) < 1e-9 && cells >= 1, "\(cells) cells go round")
        // The mean radius of a 40 mm cube about an axis through it is near 0.87 × 10 + ..., about 15 mm: 2π × 15 / 8 is about 12 cells.
        #expect((8...16).contains(Int(cells.rounded())), "\(cells)")
    }

    @Test func aStretchedCellIsWholeCellsAlongTheAngle() async throws {
        let wrapped = try await solid(0, Self.cylindrical.merging(["cell stretch": .vector(Vector3(2, 1, 1))]) { _, given in given })
        guard case .tpms(let lattice)? = wrapped.firstLattice, case .cylindrical(let map) = lattice.mapping else {
            Issue.record("not a cylindrical gyroid")
            return
        }
        let edge = 8 * lattice.cells.stretch.x
        let cells = map.turn / edge
        #expect(abs(cells - cells.rounded()) < 1e-9, "\(cells) cells of \(edge) mm go round")
    }

    @Test func aVoronoiLatticeMapsItsSeedsAndCopiesThemAcrossTheCut() async throws {
        let wrapped = try await solid(2, Self.cylindrical)
        guard case .voronoi(let lattice)? = wrapped.firstLattice else { Issue.record("not Voronoi"); return }
        #expect(lattice.seeds.realCount == 40 && lattice.seeds.ghostCount > 0)
        #expect(wrapped.description.contains("40 seeds") && wrapped.description.contains("cylindrical"))
    }

    // MARK: With the skin, the blend, a graded cell and a stretch

    @Test(arguments: LatticeMappingNodeTests.nodes.indices)
    func aSkinAndItsBlendWorkWithAMapping(_ index: Int) async throws {
        let wrapped = try await solid(index, Self.cylindrical.merging(["skin": .number(1.5), "blend": .number(1)]) { _, given in given })
        #expect(wrapped.description.hasPrefix("union(shell("), "\(wrapped.description)")
        #expect(wrapped.description.contains("blend 1 mm") && wrapped.description.contains("cylindrical"))
        // The 40 mm cube keeps a solid wall 1.5 mm thick: solid at 19.2 mm from its centre, whatever the lattice does inside.
        for point in [Vector3(19.2, 3, -2), Vector3(-4, 19.4, 5), Vector3(7, -6, 19.1)] { #expect(wrapped.signedDistance(at: point) < 0) }
        #expect(wrapped.signedDistance(at: Vector3(20.5, 0, 0)) > 0, "and nothing outside the region")
        let without = try await solid(index, Self.cylindrical)
        #expect(wrapped.lipschitz >= without.lipschitz - 1e-9, "the join only adds")
    }

    @Test func aStretchedGradedGyroidKeepsBothInItsBoundAndItsPattern() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let ramp = h.add(LinearGradientNode.self, ["length": .number(40)])
        let range: [SocketName: ConstantValue] = [
            "fromLow": .number(-0.5), "fromHigh": .number(0.5), "toLow": .number(6), "toHigh": .number(10),
        ]
        let sized = h.add(FieldRemapNode.self, range)
        let node = h.add(TPMSNode.self, Self.spherical.merging(["cell stretch": .vector(Vector3(1, 1, 2))]) { _, given in given })
        h.wire(ramp, "field", to: sized, "field")
        h.wire(box, "implicit", to: node, "region")
        h.wire(sized, "field", to: node, "cell size")
        let report = try await h.run([node])
        let solid = try #require(report.implicitSolid(node))
        guard case .tpms(let lattice)? = solid.firstLattice else { Issue.record("no gyroid"); return }
        #expect(lattice.cells.size.slope > 0 && abs(lattice.cells.stretch.z / lattice.cells.stretch.x - 2) < 1e-9)
        guard case .spherical(let map) = lattice.mapping else { Issue.record("not spherical"); return }
        #expect(lattice.lipschitz > map.stretch, "the stretch of the mapping multiplies the lattice's own bound")
    }

    // MARK: Refusals

    @Test func anAxisWithNoDirectionIsRefused() async throws {
        var h = Harness()
        let flat = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        let node = lattice(&h, 0, Self.cylindrical.merging(["axis": .plane(flat)]) { _, given in given })
        #expect(try await h.run([node]).error(node) == "“axis” has no usable direction.")
    }

    @Test func aCentreThatIsNotFiniteIsRefused() async throws {
        var h = Harness()
        let node = lattice(&h, 0, Self.spherical.merging(["centre": .vector(Vector3(.infinity, 0, 0))]) { _, given in given })
        #expect(try await h.run([node]).error(node) == "“centre” isn't a finite position.")
    }

    @Test func aMappingThatIsNotOneIsRefusedInWords() async throws {
        var h = Harness()
        let node = lattice(&h, 0, ["mapping": .integer(9)])
        #expect(try await h.run([node]).error(node) == "Choose Straight, Cylindrical, Spherical, or Face for “mapping”.")
    }

    // MARK: Warnings

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func anAxisThroughTheRegionWarnsExactly(_ index: Int) async throws {
        var h = Harness()
        let node = lattice(&h, index, Self.cylindrical)
        let warning = try #require(try await h.run([node]).warning(node))
        #expect(warning.contains("The mapping is singular near the axis; cells there are left solid."), "\(warning)")
    }

    @Test func thePolarAxisThroughTheRegionWarnsToo() async throws {
        var h = Harness()
        let node = lattice(&h, 1, Self.spherical)
        let warning = try #require(try await h.run([node]).warning(node))
        #expect(warning.contains("The mapping is singular near the polar axis; cells there are left solid."), "\(warning)")
    }

    @Test func anAxisBesideTheRegionDoesNotWarn() async throws {
        var h = Harness()
        let beside = Plane(origin: Vector3(200, 0, 0), normal: .unitZ, xAxis: .unitX)
        let node = lattice(&h, 0, Self.cylindrical.merging(["axis": .plane(beside)]) { _, given in given })
        let report = try await h.run([node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
    }

    @Test func aHollowRegionAroundTheAxisDoesNotWarn() async throws {
        // A tube of 10 mm inner radius (a cylinder of 20 less one of 10, taller so no cap coincides): the axis is in its hole, so
        // nothing is left solid there.
        var h = Harness()
        let radii = h.add(SeriesNode.self, ["start": .number(20), "step": .number(-10), "count": .integer(2)])
        let heights = h.add(SeriesNode.self, ["start": .number(30), "step": .number(10), "count": .integer(2)])
        let cylinders = h.add(ImplicitCylinderNode.self)
        h.wire(radii, "values", to: cylinders, "radius")
        h.wire(heights, "values", to: cylinders, "height")
        let tube = h.add(ImplicitSubtractNode.self)
        h.wire(cylinders, "implicit", to: tube, "shapes")
        let node = h.add(TPMSNode.self, ["cell size": .number(8), "mapping": .integer(1)])
        h.wire(tube, "implicit", to: node, "region")
        let report = try await h.run([node])
        #expect(report.error(node) == nil, "\(String(describing: report.state(node)))")
        #expect(report.warning(node)?.contains("singular") != true, "\(String(describing: report.state(node)))")
    }

    @Test func aGradedCellSizeWarnsWhereTheAngleWrapsThroughTheRegion() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let ramp = h.add(LinearGradientNode.self, ["length": .number(40)])
        let range: [SocketName: ConstantValue] = [
            "fromLow": .number(-0.5), "fromHigh": .number(0.5), "toLow": .number(6), "toHigh": .number(10),
        ]
        let sized = h.add(FieldRemapNode.self, range)
        h.wire(ramp, "field", to: sized, "field")
        let node = h.add(TPMSNode.self, Self.cylindrical)
        h.wire(box, "implicit", to: node, "region")
        h.wire(sized, "field", to: node, "cell size")
        let warning = try #require(try await h.run([node]).warning(node))
        #expect(warning.contains("The cell size is graded, so cells may not meet where the angle wraps round."), "\(warning)")
    }

    @Test func aSmallRadiusOverTheRegionWarnsThatThePreviewMayBeSlow() async throws {
        // Cells of 8 mm in a 40 mm cube about the axis: the stretch near the exclusion is the radius, about 13.
        var h = Harness()
        let node = lattice(&h, 0, Self.cylindrical)
        let warning = try #require(try await h.run([node]).warning(node))
        #expect(warning.contains("the preview may be slow"), "\(warning)")
    }

    // MARK: Files

    /// A graph saved before 7c-4 has no `mapping`, `axis` or `centre`: it reads Straight, with the geometry it had.
    @Test(arguments: LatticeMappingNodeTests.nodes.indices)
    func aFileWithoutAMappingReadsStraightWithTheSameGeometry(_ index: Int) async throws {
        var h = Harness()
        var old = lattice(&h, index)
        for key: SocketName in ["mapping", "axis", "centre"] { old.inputValues[key] = nil }
        var graph = h.graph
        graph.nodes[old.id] = old
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 2 && loaded.inputValues["mapping"] == nil, "nothing is added to the node")
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [old.id])
        let reopened = try #require(report.implicitSolid(old))
        let current = try await solid(index)
        let points = ImplicitSolidPropertyTestsPoints.points
        #expect(reopened.description == current.description)
        #expect(reopened.signedDistances(at: points) == current.signedDistances(at: points), "byte-identical geometry")
        #expect(LatticeMappingSetup.kind(of: loaded) == .straight)
    }

    @Test(arguments: LatticeMappingNodeTests.nodes.indices)
    func theMappingAndItsInputsSurviveASaveAndReopen(_ index: Int) async throws {
        let axis = Plane(origin: Vector3(1, 2, 3), normal: .unitY, xAxis: .unitZ)
        let extra: [SocketName: ConstantValue] = ["mapping": .integer(1), "axis": .plane(axis), "centre": .vector(Vector3(4, 5, 6))]
        var h = Harness()
        let node = lattice(&h, index, extra)
        let data = try GraphFileIO.encode(GraphFile(graph: h.graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[node.id])
        for (key, value) in extra { #expect(loaded.inputValues[key] == value, "\(key)") }
        #expect(file.graph.nodes == h.graph.nodes)
        #expect(GraphFile.currentFormatVersion == 8, "the mapping is an ordinary setting of format 8")
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [node.id])
        #expect(try #require(report.implicitSolid(node)).description.contains("cylindrical"))
    }

    // MARK: Inspector

    /// Controls of the Mapping section of a node set to `mapping`.
    func mappingControls(_ index: Int, _ mapping: Int) -> [InspectorControl] {
        let definition = Self.nodes[index].definition
        var node = BuiltInNodes.registry.makeNode(definition.typeID)
        node.inputValues["mapping"] = .integer(mapping)
        return definition.inspector(for: node).first { $0.title == "Mapping" }?.controls ?? []
    }

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func onlyTheActiveMappingsInputsShow(_ index: Int) {
        let segmented = InspectorControl.segmented("mapping", options: LatticeMappingKind.options)
        let straight = mappingControls(index, 0)
        #expect(straight == [segmented, .note(LatticeMappingKind.straight.help)])
        let cylindrical = mappingControls(index, 1)
        #expect(cylindrical == [segmented, .planePicker("axis"), .note(LatticeMappingKind.cylindrical.help)])
        let spherical = mappingControls(index, 2)
        #expect(spherical == [segmented, .vector("centre"), .note(LatticeMappingKind.spherical.help)])
        let face = mappingControls(index, 3)
        let pick = InspectorControl.button(title: "Pick Face in View…", action: .pickFacesInView)
        #expect(face == [segmented, .faceStatus(NodeSetting.face), pick, .note(LatticeMappingKind.face.help)])
    }

    @Test(arguments: LatticeMappingNodeTests.nodes.indices) func aNodeWithNoMappingStoredShowsStraight(_ index: Int) {
        let definition = Self.nodes[index].definition
        var node = BuiltInNodes.registry.makeNode(definition.typeID)
        node.inputValues["mapping"] = nil
        let controls = definition.inspector(for: node).flatMap(\.controls)
        #expect(!controls.contains(.planePicker("axis")) && !controls.contains(.vector("centre")))
        #expect(definition.inspector.flatMap(\.controls).contains(.segmented("mapping", options: LatticeMappingKind.options)))
    }
}

/// A fixed set of points through the 40 mm cube the tests fill.
enum ImplicitSolidPropertyTestsPoints {
    static let points: [Vector3] = {
        let random = SeededRandom(seed: 3, stream: 9)
        return (0..<400).map { Vector3(40 * random.unit(at: 3 * $0) - 20, 40 * random.unit(at: 3 * $0 + 1) - 20,
                                       40 * random.unit(at: 3 * $0 + 2) - 20) }
    }()
}

extension ImplicitSolid {
    /// The first lattice in the tree: the node's output is the lattice cut to the region, with the skin if there is one.
    var firstLattice: ImplicitSolid? {
        switch self {
        case .tpms, .struts, .voronoi: self
        default: children.lazy.compactMap(\.firstLattice).first
        }
    }
}
