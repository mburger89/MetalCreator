import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// The layouts met by the inputs a person is likely to give them (the plan's Review Focus): other nodes' trees, edges that
/// aren't straight or round, a pick on a face of a copy that is gone.
struct LayoutReviewTests {
    @Test func aLinearPatternNamesItsHolesByIndexAndACircularOneByRingAndIndex() async throws {
        for (layout, expected) in [(LinearPatternNode.self as any NodeDefinition.Type, Set([[0], [1], [2], [3]])),
                                   (CircularPatternNode.self, Set([[0, 0], [0, 1], [0, 2], [0, 3]])),
        ] {
            var plate = PatternPlate()
            let placements = plate.h.add(layout, ["count": .integer(4), "rings": .integer(1)])
            let holes = plate.h.add(HolePatternNode.self, ["diameter": .number(3), "depth": .number(3)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(placements, "placements", to: holes, "placements")
            let report = try await plate.h.run([holes], kernel: OCCTKernel())
            let part = try onlySolid(report, holes)
            let qualifier = NodeID.instanceScoped([holes.id, holes.id])
            let items = Set(part.topology.faces.flatMap(\.tags).filter { $0.node == qualifier }.map(\.item))
            #expect(Set(items.compactMap { InstancePath.indices(ofItem: $0) }) == expected, "\(layout.displayName)")
        }
    }

    /// A layout makes one tree of placements: it doesn't run once per value of a Series, so each says so in its own words
    /// (`NodeDefinition.singleValuesRefusal`), before it does any work.
    @Test func aListWiredIntoALayoutIsRefusedInTheLayoutsOwnWords() async throws {
        let layouts: [(any NodeDefinition.Type, SocketName)] = [
            (LinearPatternNode.self, "spacing"), (GridPatternNode.self, "spacingX"), (CircularPatternNode.self, "radius"),
            (CurvePatternNode.self, "spacing"), (FacePatternNode.self, "spacingX"),
        ]
        for (layout, input) in layouts {
            var plate = PatternPlate()
            let series = plate.h.add(SeriesNode.self, ["count": .integer(3)])
            let node = plate.h.add(layout)
            plate.h.wire(series, "values", to: node, input)
            if layout == FacePatternNode.self { plate.h.wire(plate.plate, "solid", to: node, "solid") }
            let report = try await plate.h.run([node], kernel: FakeKernel())
            #expect(report.error(node) == "\(layout.displayName) takes single values, not lists: wire one value into each input, "
                + "or pick one out of the list first with List Item.", "\(layout.displayName)")
        }
    }

    @Test func aCircularPatternIntoPlaceMakesOneKernelCallAndATreeOfCopies() async throws {
        var plate = PatternPlate()
        let rings = plate.h.add(CircularPatternNode.self, ["count": .integer(3), "rings": .integer(2), "countStep": .integer(1)])
        let tool = plate.cylinder(diameter: 2, from: 0, to: 2)
        let place = plate.h.add(PlaceNode.self)
        plate.h.wire(rings, "placements", to: place, "placements")
        plate.h.wire(tool, "solid", to: place, "tool")
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await plate.h.run([place], kernel: kernel)
        let tree = try #require(report.value(place, "solids")?.asTree, "\(String(describing: report.state(place)))")
        #expect(tree.leaves.map { $0.items.count } == [3, 4])
        #expect(await kernel.operationLog.filter { $0 == "place" }.count == 1)
    }

    @Test func anEdgeThatIsNeitherStraightNorRoundIsRefusedNamingIt() async throws {
        let box = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 5, mode: .oneSided,
                                                 tag: NodeTag(node: NodeID(), item: 0))
        var topology = box.topology
        topology.edges[0].curve = nil
        let solid = Solid(topology: topology, bounds: box.bounds, storage: box.storage)
        let node = BuiltInNodes.registry.makeNode(CurvePatternNode.typeID)
        let inputs = NodeInputs(item: 0, slots: [
            "edges": .list([.edgeSet(EdgeSet(solid: solid, edges: [topology.edges[0].id]))]),
            "mode": .item(.integer(0)), "count": .item(.integer(3)), "spacing": .item(.number(10)),
        ])
        let context = EvalContext(node: node, item: 0, parameters: [:])
        let id = topology.edges[0].id.rawValue
        await #expect(throws: NodeError.invalidValue("Curve Pattern follows straight and circular edges for now: "
            + "edge \(id) is another kind of curve.")) {
            _ = try await CurvePatternNode.evaluate(inputs, kernel: FakeKernel(), context: context)
        }
    }

    @Test func aFacePatternOnTheFloorOfAHoleThatIsGoneNamesTheHole() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate()
        let rings = plate.h.add(CircularPatternNode.self, ["count": .integer(4), "radius": .number(10), "rings": .integer(2)])
        let holes = plate.h.add(HolePatternNode.self, ["diameter": .number(4), "depth": .number(3)])
        let pattern = plate.h.add(FacePatternNode.self, ["margin": .number(0.5), "spacingX": .number(1), "spacingY": .number(1)])
        plate.h.wire(plate.plate, "solid", to: holes, "part")
        plate.h.wire(rings, "placements", to: holes, "placements")
        plate.h.wire(holes, "solid", to: pattern, "solid")
        let drilled = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
        let qualifier = NodeID.instanceScoped([holes.id, holes.id])
        let item = try #require(InstancePath.item(for: [1, 2]))
        // The floor of hole {1;2}: flat, facing up, three millimetres down, and named by that hole.
        let floor = try #require(drilled.topology.faces.first { face in
            face.kind == .plane && face.normal == .unitZ && abs(face.centroid.z + 3) < 1e-6
                && face.tags.contains { $0.node == qualifier && $0.item == item }
        })
        plate.h.set(pattern, NodeSetting.face, .facePick(try #require(drilled.topology.facePick(for: floor.id))))
        #expect(try await plate.h.run([pattern], kernel: kernel).isOK(pattern))
        plate.h.set(rings, "rings", .integer(1))
        let report = try await plate.h.run([pattern], kernel: kernel)
        #expect(report.error(pattern) == "Instance {1;2} no longer exists, so the picked face isn't there any more. Pick the face again.")
    }

    // MARK: Review findings of Tasks 1 to 8

    /// A layout's numbers and points are finite: NaN or infinity would turn every placement to NaN, so each refuses by name.
    struct NotFinite: CustomTestStringConvertible {
        let what: String
        let layout: any NodeDefinition.Type
        let settings: [SocketName: ConstantValue]
        let message: String
        var testDescription: String { what }
    }

    @Test(arguments: [
        NotFinite(what: "a Circular Pattern radiusStep of infinity", layout: CircularPatternNode.self,
                  settings: ["radiusStep": .number(.infinity)], message: "“radiusStep” must be a finite number."),
        NotFinite(what: "a Circular Pattern radiusStep of NaN", layout: CircularPatternNode.self,
                  settings: ["radiusStep": .number(.nan)], message: "“radiusStep” must be a finite number."),
        NotFinite(what: "a Circular Pattern centre with NaN", layout: CircularPatternNode.self,
                  settings: ["centre": .vector(Vector3(.nan, 0, 0))], message: "“centre” must be a finite point."),
        NotFinite(what: "a Linear Pattern start with infinity", layout: LinearPatternNode.self,
                  settings: ["start": .vector(Vector3(0, .infinity, 0))], message: "“start” must be a finite point."),
        NotFinite(what: "a Grid Pattern plane with an origin of NaN", layout: GridPatternNode.self,
                  settings: ["plane": .plane(Plane(origin: Vector3(.nan, 0, 0), normal: .unitZ, xAxis: .unitX))],
                  message: "The grid's plane has no usable direction."),
    ])
    func aLayoutRefusesANumberOrPointThatIsNotFinite(_ row: NotFinite) async throws {
        var h = Harness()
        let node = h.add(row.layout, row.settings)
        let report = try await h.run([node])
        #expect(report.error(node) == row.message)
    }

    /// The evaluator's guard (`plan.iterations > 1`) for a count and a radius: a list into either would run the layout once per
    /// value without it. The counts come from Tree Statistics (the one source of a list of whole numbers), three branches of 2.
    @Test(arguments: ["countX", "radius"])
    func aListIntoACountOrARadiusIsRefusedBeforeTheLayoutRuns(_ input: String) async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(2), "count": .integer(6)])
        let parts = h.add(PartitionNode.self, ["size": .integer(2)])
        let statistics = h.add(TreeStatisticsNode.self)
        h.wire(series, "values", to: parts, "tree")
        h.wire(parts, "tree", to: statistics, "tree")
        let layout: any NodeDefinition.Type = input == "countX" ? GridPatternNode.self : CircularPatternNode.self
        let node = h.add(layout)
        h.wire(input == "countX" ? statistics : series, input == "countX" ? "counts" : "values", to: node, SocketName(input))
        let report = try await h.run([node])
        #expect(report.error(node) == "\(layout.displayName) takes single values, not lists: wire one value into each input, "
            + "or pick one out of the list first with List Item.")
    }

    @Test func aNodeWithoutTheRefusalStillBroadcastsAListOverItsRuns() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(2), "count": .integer(3)])
        let profile = h.add(RectangleNode.self)
        let extrude = h.add(ExtrudeNode.self)
        h.wire(profile, "profile", to: extrude, "profile")
        h.wire(series, "values", to: extrude, "distance")
        let report = try await h.run([extrude])
        #expect(report.isOK(extrude))
        #expect(report.value(extrude, "solid")?.solids?.map { $0.bounds.max.z - $0.bounds.min.z } == [2, 3, 4])
    }

    @Test func aPlaceWithNoPlacementsMakesNoKernelCallAndNoCopies() async throws {
        var plate = PatternPlate()
        let none = plate.h.add(LinearPatternNode.self, ["count": .integer(0)])
        let tool = plate.cylinder(diameter: 2, from: 0, to: 2)
        let place = plate.h.add(PlaceNode.self)
        plate.h.wire(none, "placements", to: place, "placements")
        plate.h.wire(tool, "solid", to: place, "tool")
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await plate.h.run([place], kernel: kernel)
        #expect(report.isOK(place))
        #expect(report.value(place, "solids")?.items.isEmpty == true)
        #expect(await kernel.operationLog.contains("place") == false)
    }
}
