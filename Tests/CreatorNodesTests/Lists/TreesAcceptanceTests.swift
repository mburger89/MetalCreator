import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// 7a spec §9, headless: a plate with holes laid out by a data tree. Grid Points → Partition (rows) → Circle → Extrude
/// → Boolean, whose `tools` gets one branch per run, so each row of holes cuts its own copy of the plate. A Path Mapper
/// transposes the rows, a parameter changes the row length, and the file is saved (format 6), reopened and exported.
@MainActor
struct TreesAcceptanceTests {
    struct Plate {
        var graph: Graph
        let partition: Node
        let holes: Node
        let cut: Node
        let output: Node
    }

    /// 8 grid points (4 × 2) in rows of 4 → circles Ø5 → symmetric 20 mm extrusions → subtracted from a 60 × 40 × 6 plate.
    static func makePlate() -> Plate {
        var h = Harness()
        let plate = h.box(60, 40, 6)
        let grid = h.add(GridPointsNode.self, ["countX": .integer(4), "countY": .integer(2),
                                               "spacingX": .number(12), "spacingY": .number(12),
        ])
        let partition = h.add(PartitionNode.self, ["size": .integer(4)])
        h.wire(grid, "points", to: partition, "tree")
        let circle = h.add(CircleNode.self, ["diameter": .number(5)])
        h.wire(partition, "tree", to: circle, "plane")
        let holes = h.add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        h.wire(circle, "profile", to: holes, "profile")
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        h.wire(plate, "solid", to: cut, "target")
        h.wire(holes, "solid", to: cut, "tools")
        let output = h.add(OutputNode.self)
        h.wire(cut, "solid", to: output, "solid")
        return Plate(graph: h.graph, partition: partition, holes: holes, cut: cut, output: output)
    }

    func solids(_ document: DocumentModel, _ node: Node) throws -> [Solid] {
        try #require(document.results[node.id]?.outputs?["solid"]?.solids)
    }

    func expectAllOK(_ document: DocumentModel, _ when: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let problems = document.results.compactMap { id, result -> String? in
            if case .ok = result.state { return nil }
            return "\(document.graph.nodes[id]?.name ?? "?"): \(result.state)"
        }
        #expect(problems.isEmpty, "\(when): \(problems.sorted().joined(separator: "; "))", sourceLocation: sourceLocation)
    }

    /// The faces of `holes` item `k` are in the solid: the hole made from the k-th point of the tree, counted row by row.
    func hasHole(_ solid: Solid, _ holes: Node, item: Int) -> Bool {
        solid.topology.faces.contains { $0.tags.contains(TopoTag(node: holes.id, item: item, role: .side(segment: 0))) }
    }

    @Test func eachRowOfHolesCutsItsOwnCopyOfThePlate() async throws {
        let kernel = OCCTKernel()
        let plate = Self.makePlate()
        let document = DocumentModel(file: GraphFile(graph: plate.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        expectAllOK(document, "two rows of four")
        let copies = try solids(document, plate.cut)
        #expect(copies.count == 2)
        let base = 60.0 * 40 * 6, hole = Double.pi * 6.25 * 6
        for copy in copies {
            #expect(isClose(try await volume(copy, kernel), base - 4 * hole))
        }
        // Holes are named by their place in the tree read row by row: the first row's are 0 to 3, the second's 4 to 7.
        #expect((0..<4).allSatisfy { hasHole(copies[0], plate.holes, item: $0) })
        #expect((4..<8).allSatisfy { hasHole(copies[1], plate.holes, item: $0) })
        #expect(!hasHole(copies[0], plate.holes, item: 4))
        #expect(document.results[plate.holes.id]?.outputs?["solid"]?.depth == 2)
    }

    @Test func aPathMapperTransposesTheRowsIntoColumns() async throws {
        let kernel = OCCTKernel()
        let plate = Self.makePlate()
        var h = Harness()
        let mapper = h.add(PathMapperNode.self, [NodeSetting.pathRule: .text("{A} → {(i)}")])
        // Between Partition and Circle, as one undo step would: the wire into Circle now comes from the mapper.
        let circleLink = try #require(plate.graph.links.first { $0.to.socket == "plane" })
        let document = DocumentModel(file: GraphFile(graph: plate.graph), registry: BuiltInNodes.registry, kernel: kernel)
        try document.perform(.batch([
            .addNode(mapper),
            .connect(Link(from: Endpoint(node: plate.partition.id, socket: "tree"), to: Endpoint(node: mapper.id, socket: "tree"))),
            .connect(Link(from: Endpoint(node: mapper.id, socket: "tree"), to: circleLink.to)),
        ]))
        await document.waitForEvaluation()
        expectAllOK(document, "transposed")
        let columns = try solids(document, plate.cut)
        #expect(columns.count == 4, "4 columns of 2 holes")
        let base = 60.0 * 40 * 6, hole = Double.pi * 6.25 * 6
        for column in columns {
            #expect(isClose(try await volume(column, kernel), base - 2 * hole))
        }
        // The mapper's tree is 4 branches of 2 (the partition's was 2 of 4), and branch {c} holds column c: the same x, a row apart.
        let mapped = try #require(document.results[mapper.id]?.outputs?["tree"]?.asTree)
        #expect(mapped.leaves.map(\.path.indices) == [[0], [1], [2], [3]])
        #expect(mapped.leaves.allSatisfy { $0.items.count == 2 })
        let columnPoints = mapped.leaves.map { $0.items.compactMap { if case .vector(let point) = $0 { point } else { nil } } }
        #expect(columnPoints.allSatisfy { $0.count == 2 })
        #expect(columnPoints.allSatisfy { abs($0[0].x - $0[1].x) < 1e-9 && abs($0[1].y - $0[0].y - 12) < 1e-9 })
        #expect(abs(columnPoints[1][0].x - columnPoints[0][0].x - 12) < 1e-9)
        // The holes are named by their place in the mapped tree: column 0 has items 0 and 1, column 1 has 2 and 3.
        #expect(hasHole(columns[0], plate.holes, item: 0) && hasHole(columns[0], plate.holes, item: 1))
        #expect(hasHole(columns[1], plate.holes, item: 2) && !hasHole(columns[1], plate.holes, item: 0))
    }

    @Test func changingTheRowLengthReshapesTheResultAndTheFileRoundTripsAsFormatSix() async throws {
        let kernel = OCCTKernel()
        let plate = Self.makePlate()
        let document = DocumentModel(file: GraphFile(graph: plate.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        try document.perform(.setInput(plate.partition.id, "size", .integer(2)))
        await document.waitForEvaluation()
        expectAllOK(document, "rows of two")
        let copies = try solids(document, plate.cut)
        #expect(copies.count == 4)
        let base = 60.0 * 40 * 6, hole = Double.pi * 6.25 * 6
        for copy in copies {
            #expect(isClose(try await volume(copy, kernel), base - 2 * hole))
        }

        // Save and reopen.
        let data = try document.fileData()
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 6"#))
        let reopened = try DocumentModel(data: data, registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        expectAllOK(reopened, "reopened")
        #expect(try solids(reopened, plate.cut).count == 4)

        // The same file marked format 5 opens and evaluates the same: nothing in it needs 6.
        let asFive = try #require(String(bytes: data, encoding: .utf8)).replacing(#""formatVersion" : 6"#, with: #""formatVersion" : 5"#)
        let older = try DocumentModel(data: Data(asFive.utf8), registry: BuiltInNodes.registry, kernel: kernel)
        await older.waitForEvaluation()
        expectAllOK(older, "format 5")
        #expect(try solids(older, plate.cut).count == 4)

        // STEP export of every copy succeeds and reads back.
        let step = URL.temporaryDirectory.appending(path: "trees-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: step) }
        try await kernel.export(copies, format: .step, to: step)
        let readVolume = try OCCTKernel.serialized { () throws -> Double in try OCCTShape.readSTEP(step).properties().volume }
        #expect(readVolume > 0)
    }

    @Test func aRuleThatCannotApplyShowsTheMessageAndThePartWaits() async throws {
        let plate = Self.makePlate()
        var h = Harness()
        let mapper = h.add(PathMapperNode.self, [NodeSetting.pathRule: .text("{A;B;C} → {A}")])
        let circleLink = try #require(plate.graph.links.first { $0.to.socket == "plane" })
        let document = DocumentModel(file: GraphFile(graph: plate.graph), registry: BuiltInNodes.registry, kernel: OCCTKernel())
        try document.perform(.batch([
            .addNode(mapper),
            .connect(Link(from: Endpoint(node: plate.partition.id, socket: "tree"), to: Endpoint(node: mapper.id, socket: "tree"))),
            .connect(Link(from: Endpoint(node: mapper.id, socket: "tree"), to: circleLink.to)),
        ]))
        await document.waitForEvaluation()
        guard case .error(let message)? = document.results[mapper.id]?.state else { Issue.record("expected an error"); return }
        #expect(message.hasPrefix("The rule's source {A;B;C} names 3 levels, but this tree (2 × 4) has 1 level of branches."))
        guard case .idle? = document.results[plate.cut.id]?.state else { Issue.record("the cut should wait"); return }
    }
}
