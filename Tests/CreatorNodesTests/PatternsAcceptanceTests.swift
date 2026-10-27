import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// Patterns spec §9, headless, in the spirit of the bracket: a 120 × 80 × 8 plate with a circular bolt pattern in two rings
/// whose holes are a diameter per ring, a staggered vent grid of slots on its top face with an edge margin (the Face Pattern
/// keeps clear of the bolt holes too), and a fillet on one patterned hole, the one at `{1;3}`. Parameters change, the file is
/// saved (format 6) and reopened, every pick holds, STEP export succeeds, and the same file marked format 5 opens unchanged.
@MainActor
struct PatternsAcceptanceTests {
    struct Part {
        var graph: Graph
        let ring: Node, bolts: Node, vents: Node, slots: Node, rule: Node, fillet: Node, output: Node
    }

    /// Plate → Hole Pattern (bolt circle, Ø6 then Ø4 by ring) → Slot Pattern (vents, at a staggered Face Pattern of the
    /// drilled plate's top) → Edges by Tag (the rim of the bolt hole `{1;3}`) → Fillet → Output.
    static func makePart(kernel: any Kernel) async throws -> Part {
        var h = Harness()
        let plate = h.box(120, 80, 8, at: Vector3(0, 0, -8))
        let ring = h.add(CircularPatternNode.self, ["radius": .number(15), "count": .integer(4), "countStep": .integer(4),
                                                    "rings": .integer(2), "radiusStep": .number(10),
        ])
        let diameters = h.add(SeriesNode.self, ["start": .number(6), "step": .number(-2), "count": .integer(2)])
        let perRing = h.add(GraftNode.self)
        let bolts = h.add(HolePatternNode.self, ["throughAll": .bool(true)])
        h.wire(plate, "solid", to: bolts, "part")
        h.wire(ring, "placements", to: bolts, "placements")
        h.wire(diameters, "values", to: perRing, "tree")
        h.wire(perRing, "tree", to: bolts, "diameter")
        let vents = h.add(FacePatternNode.self, ["spacingX": .number(14), "spacingY": .number(12), "stagger": .bool(true),
                                                 "margin": .number(6),
        ])
        h.wire(bolts, "solid", to: vents, "solid")
        let slots = h.add(SlotPatternNode.self, ["length": .number(8), "width": .number(3), "throughAll": .bool(true)])
        h.wire(bolts, "solid", to: slots, "part")
        h.wire(vents, "placements", to: slots, "placements")
        let rule = h.add(EdgesByTagNode.self)
        h.wire(slots, "solid", to: rule, "solid")
        let fillet = h.add(FilletNode.self, ["radius": .number(0.5)])
        h.wire(rule, "edges", to: fillet, "edges")
        let output = h.add(OutputNode.self)
        h.wire(fillet, "solid", to: output, "solid")

        // The picks, made the way the app makes them: the top face of the drilled plate, then the rim of hole {1;3} on the result.
        let drilled = try onlySolid(try await h.run([bolts], kernel: kernel), bolts)
        let top = try #require(drilled.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
            .max { $0.centroid.z < $1.centroid.z })
        h.set(vents, NodeSetting.face, .facePick(try #require(drilled.topology.facePick(for: top.id))))
        let slotted = try onlySolid(try await h.run([slots], kernel: kernel), slots)
        let bore = TopoTag(node: NodeID.instanceScoped([bolts.id, bolts.id]), item: try #require(InstancePath.item(for: [1, 3])),
                           role: .side(segment: 1))
        let capTag = TopoTag(node: plate.id, item: 0, role: .endCap)
        let rim = try #require(slotted.topology.edges.first { edge in
            guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
            let sides = edge.faces.compactMap { slotted.topology.face($0) }
            return sides.contains { $0.tags.contains(bore) } && sides.contains { $0.tags.contains(capTag) }
        })
        h.set(rule, NodeSetting.picks, .edgePicks(slotted.topology.picks(for: [rim.id])))
        return Part(graph: h.graph, ring: ring, bolts: bolts, vents: vents, slots: slots, rule: rule, fillet: fillet, output: output)
    }

    func expectAllOK(_ document: DocumentModel, _ when: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let problems = document.results.compactMap { id, result -> String? in
            if case .ok = result.state { return nil }
            return "\(document.graph.nodes[id]?.name ?? "?"): \(result.state)"
        }
        #expect(problems.isEmpty, "\(when): \(problems.sorted().joined(separator: "; "))", sourceLocation: sourceLocation)
    }

    func finalSolid(_ document: DocumentModel, _ part: Part) throws -> Solid {
        try #require(document.results[part.output.id]?.outputs?["solid"]?.solids?.first)
    }

    /// The paths of the instances of `node` that have faces in `solid`.
    func paths(of node: Node, in solid: Solid) -> Set<[Int]> {
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        let items = Set(solid.topology.faces.flatMap(\.tags).filter { $0.node == qualifier }.map(\.item))
        return Set(items.compactMap { InstancePath.indices(ofItem: $0) })
    }

    /// Whether the fillet's blend faces name the bore of the hole at `path`.
    func isFilleted(_ solid: Solid, hole path: [Int], bolts: Node) -> Bool {
        let bore = TopoTag(node: NodeID.instanceScoped([bolts.id, bolts.id]), item: InstancePath.item(for: path) ?? -1,
                           role: .side(segment: 1))
        return solid.topology.faces.contains { face in
            face.tags.contains { tag in
                if case .blend(let edge) = tag.role { edge.first.union(edge.second).contains(bore) } else { false }
            }
        }
    }

    #if canImport(CreatorOCCT)
    @Test func theWholePartBuildsEditsSavesReopensAndExports() async throws {
        let kernel = OCCTKernel()
        let part = try await Self.makePart(kernel: kernel)
        let document = DocumentModel(file: GraphFile(graph: part.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        expectAllOK(document, "as built")
        let built = try finalSolid(document, part)
        // Two rings of 4 and 8 bolt holes, each hole named by its ring and place; the vents are Face Pattern's rows.
        #expect(paths(of: part.bolts, in: built).count == 12 && paths(of: part.bolts, in: built).allSatisfy { $0.count == 2 })
        let placements = try #require(document.results[part.vents.id]?.outputs?["placements"]?.asTree)
        let ventPaths = Set(placements.leaves.flatMap { leaf in leaf.items.indices.map { leaf.path.indices + [$0] } })
        #expect(paths(of: part.slots, in: built) == ventPaths && ventPaths.count > 10, "\(ventPaths.count) vents")
        #expect(isFilleted(built, hole: [1, 3], bolts: part.bolts))
        // Per-ring diameters: the bores of ring 0 are Ø6 and ring 1's Ø4, through 8 mm of plate (the filleted hole {1;3} aside).
        let bolt = NodeID.instanceScoped([part.bolts.id, part.bolts.id])
        let bores = built.topology.faces.filter { $0.kind == .cylinder && $0.tags.contains { $0.node == bolt } }
        func areas(ring: Int) -> [Double] {
            bores.filter { face in face.tags.contains { InstancePath.indices(ofItem: $0.item)?.first == ring && $0.node == bolt } }
                .filter { face in !face.tags.contains { $0.item == InstancePath.item(for: [1, 3]) } }.map(\.area)
        }
        #expect(areas(ring: 0).count == 4 && areas(ring: 0).allSatisfy { isClose($0, Double.pi * 6 * 8, relative: 1e-4) })
        #expect(areas(ring: 1).count == 7 && areas(ring: 1).allSatisfy { isClose($0, Double.pi * 4 * 8, relative: 1e-4) })

        // Change the pattern: a bigger bolt circle with a third ring, wider vents, a smaller margin.
        try document.perform(.setInput(part.ring.id, "radius", .number(16)))
        try document.perform(.setInput(part.ring.id, "rings", .integer(3)))
        try document.perform(.setInput(part.vents.id, "spacingX", .number(15)))
        try document.perform(.setInput(part.vents.id, "margin", .number(5)))
        await document.waitForEvaluation()
        expectAllOK(document, "after the edits")
        let edited = try finalSolid(document, part)
        #expect(paths(of: part.bolts, in: edited).count == 24, "4 + 8 + 12 holes")
        #expect(isFilleted(edited, hole: [1, 3], bolts: part.bolts), "the fillet is still on the hole at {1;3}")
        #expect(document.results[part.rule.id]?.state.isSuccess == true)

        // Save and reopen: format 7, every pick holds.
        let data = try document.fileData()
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""formatVersion" : \#(GraphFile.currentFormatVersion)"#))
        let reopened = try DocumentModel(data: data, registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        expectAllOK(reopened, "reopened")
        let again = try finalSolid(reopened, part)
        #expect(isFilleted(again, hole: [1, 3], bolts: part.bolts))
        #expect(isClose(try await volume(again, kernel), try await volume(edited, kernel)))
        #expect(paths(of: part.slots, in: again) == paths(of: part.slots, in: edited))

        // STEP export of the finished part succeeds and reads back.
        let step = URL.temporaryDirectory.appending(path: "patterns-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: step) }
        try await kernel.export([again], format: .step, to: step)
        let readVolume = try OCCTKernel.serialized { () throws -> Double in try OCCTShape.readSTEP(step).properties().volume }
        #expect(isClose(readVolume, try await volume(again, kernel), relative: 1e-3))

        // The same file marked format 5 opens and evaluates the same: nothing in it needs 6 (it holds no Path Mapper).
        let asFive = text.replacing(#""formatVersion" : \#(GraphFile.currentFormatVersion)"#, with: #""formatVersion" : 5"#)
        let older = try DocumentModel(data: Data(asFive.utf8), registry: BuiltInNodes.registry, kernel: kernel)
        await older.waitForEvaluation()
        expectAllOK(older, "format 5")
        #expect(isClose(try await volume(try finalSolid(older, part), kernel), try await volume(edited, kernel)))
    }

    /// Spec §9, "a format-5 file opens unchanged": `LegacyDocuments.bracketFormat5` is the bracket as the program wrote it before
    /// the tree nodes (commit 187b5ff~1: format 5, no pattern node, the chamfer's seven picked edges). Opened now it evaluates with
    /// no warning, its picks select what they selected and the part is the part it was; saved again it is format 6 and unchanged.
    @Test func aBracketWrittenAsFormat5OpensWithItsPicksAndVolumeUnchanged() async throws {
        let kernel = OCCTKernel()
        #expect(LegacyDocuments.bracketFormat5.contains(#""formatVersion":5"#))
        let document = try DocumentModel(data: Data(LegacyDocuments.bracketFormat5.utf8), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        expectAllOK(document, "format 5")
        let nodes = document.graph.nodes.values
        let output = try #require(nodes.first { $0.typeID == OutputNode.typeID })
        let rule = try #require(nodes.first { $0.typeID == EdgesByTagNode.typeID })
        func part(_ document: DocumentModel) throws -> Solid {
            try #require(document.results[output.id]?.outputs?["solid"]?.solids?.first)
        }
        let opened = try part(document)
        #expect(isClose(try await volume(opened, kernel), 25183.435985523505, relative: 1e-9))
        #expect(opened.topology.faces.count == 25 && opened.topology.edges.count == 67)
        #expect(document.results[rule.id]?.outputs?["edges"]?.edgeSets?.first?.edges.count == 7, "the seven picked edges")

        let text = try #require(String(bytes: try document.fileData(), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : \#(GraphFile.currentFormatVersion)"#))
        let saved = try DocumentModel(data: Data(text.utf8), registry: BuiltInNodes.registry, kernel: kernel)
        await saved.waitForEvaluation()
        expectAllOK(saved, "format 5 saved as 6")
        #expect(isClose(try await volume(try part(saved), kernel), try await volume(opened, kernel), relative: 1e-9))
    }

    /// Patterns spec §6: "changing spacing, position or size keeps paths". Raising the margin from 6 to 12 mm drops the vents near
    /// the edge and the bolt holes; every vent that stays keeps its path, its place on the plate and the names of its faces, so a
    /// pick on it would still be on it.
    @Test func aVentKeepsItsPathAndPlaceWhenTheMarginGrows() async throws {
        let kernel = OCCTKernel()
        let part = try await Self.makePart(kernel: kernel)
        let document = DocumentModel(file: GraphFile(graph: part.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        expectAllOK(document, "as built")
        func vents() throws -> [[Int]: Vector3] {
            let tree = try #require(document.results[part.vents.id]?.outputs?["placements"]?.asTree)
            var found: [[Int]: Vector3] = [:]
            for leaf in tree.leaves {
                for (index, item) in leaf.items.enumerated() {
                    if case .plane(let plane) = item { found[leaf.path.indices + [index]] = plane.origin }
                }
            }
            return found
        }
        /// The centres of the faces that name the vent at `path`.
        func faceCentres(_ path: [Int]) throws -> [Vector3] {
            let solid = try finalSolid(document, part)
            let qualifier = NodeID.instanceScoped([part.slots.id, part.slots.id])
            let item = try #require(InstancePath.item(for: path))
            return solid.topology.faces.filter { $0.tags.contains { $0.node == qualifier && $0.item == item } }.map(\.centroid)
        }
        func isAtItsPlace(_ path: [Int], _ origin: Vector3) throws -> Bool {
            let centres = try faceCentres(path)
            return !centres.isEmpty && centres.allSatisfy { Vector2($0.x - origin.x, $0.y - origin.y).length < 5 }
        }

        let before = try vents()
        for (path, origin) in before { #expect(try isAtItsPlace(path, origin), "as built, vent \(path)") }
        try document.perform(.setInput(part.vents.id, "margin", .number(12)))
        await document.waitForEvaluation()
        expectAllOK(document, "a bigger margin")
        let after = try vents()
        #expect(!after.isEmpty && after.count < before.count, "\(before.count) vents became \(after.count)")
        for (path, origin) in after {
            let was = try #require(before[path], "vent \(path) was not there before")
            #expect((was - origin).length < 1e-6, "vent \(path) moved")
            #expect(try isAtItsPlace(path, origin), "vent \(path)'s faces are no longer at it")
        }
    }

    @Test func aPickOnARingThatIsGoneWarnsNamingItsPath() async throws {
        let kernel = OCCTKernel()
        let part = try await Self.makePart(kernel: kernel)
        let document = DocumentModel(file: GraphFile(graph: part.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        try document.perform(.setInput(part.ring.id, "rings", .integer(1)))
        await document.waitForEvaluation()
        guard case .warning(let message)? = document.results[part.rule.id]?.state else {
            Issue.record("the rule should warn, got \(String(describing: document.results[part.rule.id]?.state))")
            return
        }
        #expect(message == "Instance {1;3} no longer exists, so the edge picked on it isn't selected.")
    }

    @Test func rotatingTheBoltCircleKeepsEveryHolesPath() async throws {
        let kernel = OCCTKernel()
        let part = try await Self.makePart(kernel: kernel)
        let document = DocumentModel(file: GraphFile(graph: part.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        try document.perform(.setInput(part.ring.id, "startAngle", .number(20)))
        await document.waitForEvaluation()
        expectAllOK(document, "rotated")
        let solid = try finalSolid(document, part)
        #expect(isFilleted(solid, hole: [1, 3], bolts: part.bolts), "the same hole, turned with the ring")
    }
    #endif
}
