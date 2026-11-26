import CreatorDrawing
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Group, Ungroup and Make Unique rename the picks a drawing's annotations hold (DR-2 R21).
@MainActor
struct DrawingAnchorRenamingTests {
    let scene = GroupScene()

    func edgePick(_ node: NodeID) -> EdgePick {
        EdgePick(key: EdgeKey([TopoTag(node: node, item: 0, role: .side(segment: 1))],
                              [TopoTag(node: node, item: 0, role: .endCap)]), matchCount: 1)
    }

    func facePick(_ node: NodeID) -> FacePick {
        FacePick(tags: [TopoTag(node: node, item: 0, role: .endCap)])
    }

    func annotations(_ node: NodeID) -> [DrawingAnnotation] {
        let dimension = DrawingDimension(kind: .linear(.horizontal),
                                         anchors: [.edge(edgePick(node)), .corner(edgePick(node), edgePick(node))],
                                         placement: DimensionPlacement(offset: 5, angle: 0))
        let note = DrawingNote(text: "N", position: Vector2(1, 1),
                               leaders: [LeaderEnd(target: .outline(facePick(node), side: Vector2(1, 0)), hint: Vector2(0, 0))])
        let callout = HoleCallout(anchor: .edge(edgePick(node)), placement: DimensionPlacement(offset: 5, angle: 0))
        return [DrawingAnnotation(view: nil, kind: .dimension(dimension)),
                DrawingAnnotation(view: nil, kind: .note(note)),
                DrawingAnnotation(view: nil, kind: .holeCallout(callout)),
                DrawingAnnotation(view: nil, kind: .centreMark(CentreMark(anchor: .edge(edgePick(node))))),
                DrawingAnnotation(view: nil, kind: .centreLine(CentreLine(anchor: .axis(facePick(node))))), ]
    }

    func document(drawingOn node: NodeID?) -> DocumentModel {
        var start = graph(scene.nodes, scene.links)
        start.sortLinks()
        if let node {
            start.drawings = DrawingDocument(sheets: [DrawingSheet(name: "S", annotations: annotations(node))])
        }
        return DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
    }

    func nodesNamed(in drawings: DrawingDocument) -> Set<NodeID> {
        var found: Set<NodeID> = []
        for annotation in drawings.sheets.flatMap(\.annotations) {
            func take(_ target: AnchorTarget) {
                switch target {
                case .edge(let p), .centre(let p): found.formUnion(p.key.first.union(p.key.second).map(\.node))
                case .corner(let a, let b):
                    found.formUnion(a.key.first.union(a.key.second).union(b.key.first).union(b.key.second).map(\.node))
                case .outline(let f, _), .axis(let f): found.formUnion(f.tags.map(\.node))
                case .point: break
                case .onPart(_, let inner): take(inner)
                }
            }
            switch annotation.kind {
            case .dimension(let d): d.anchors.forEach(take)
            case .note(let n): n.leaders.forEach { take($0.target) }
            case .holeCallout(let c): take(c.anchor)
            case .centreMark(let m): take(m.anchor)
            case .centreLine(let l): take(l.anchor)
            case .datumFeature, .featureControl, .surfaceTexture:
                if case .feature(let end)? = annotation.symbolAttachment { take(end.target) }
            case .balloon(let balloon): take(balloon.leader.target)
            case .partsList, .revisionTable: break
            }
        }
        return found
    }

    @Test func partAnchorsAreRenamed() {
        let a = NodeID(), b = NodeID(), part = NodeID()
        let wrapped = AnchorTarget.onPart(part, .edge(edgePick(a)))
        #expect(wrapped.renamingTags([a: b]) == .onPart(part, .edge(edgePick(b))))
        let balloon = DrawingAnnotation(
            view: nil, kind: .balloon(Balloon(leader: LeaderEnd(target: wrapped, hint: Vector2(1, 1)), offset: Vector2(4, 4))))
        let dimension = DrawingAnnotation(
            view: nil,
            kind: .dimension(DrawingDimension(kind: .linear(.horizontal), anchors: [wrapped],
                                              placement: DimensionPlacement(offset: 5, angle: 0))))
        let renamed = [balloon, dimension].map { $0.renamingTags([a: b]) }
        #expect(nodesNamed(in: DrawingDocument(sheets: [DrawingSheet(name: "S", annotations: renamed)])) == [b])
        let part2 = [part: part]
        #expect(wrapped.renamingTags(part2) == wrapped, "the part is an Output, never renamed")
    }

    @Test func symbolsAreRenamed() {
        let a = NodeID(), b = NodeID()
        let end = LeaderEnd(target: .edge(edgePick(a)), hint: Vector2(1, 1))
        let datum = DrawingAnnotation(
            view: nil, kind: .datumFeature(DatumFeature(letter: "A", attachment: .feature(end))))
        let frame = DrawingAnnotation(
            view: nil,
            kind: .featureControl(
                FeatureControlFrame(characteristic: .flatness, rows: [ToleranceRow(value: 0.1)], attachment: .feature(end))))
        let surface = DrawingAnnotation(
            view: nil, kind: .surfaceTexture(SurfaceTexture(requirement: SurfaceRequirement(), feature: end)))
        let renamedEnd = LeaderEnd(target: .edge(edgePick(b)), hint: Vector2(1, 1))
        for annotation in [datum, frame, surface] {
            #expect(annotation.renamingTags([a: b]).symbolAttachment == .feature(renamedEnd))
        }
        let size = AnnotationID()
        let onSize = DrawingAnnotation(
            view: nil, kind: .datumFeature(DatumFeature(letter: "B", attachment: .dimension(size))))
        #expect(onSize.renamingTags([a: b]) == onSize)
    }

    @Test func groupingKeepsADimensionHeld() throws {
        let document = document(drawingOn: scene.a1.id)
        let edit = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        let group = try #require(edit.selection.first)
        #expect(nodesNamed(in: document.graph.drawings) == [GroupScopes.identity([group, scene.a1.id])])
    }

    @Test func ungroupRenamesBack() throws {
        let document = document(drawingOn: scene.a1.id)
        let grouped = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        try document.perform(grouped.command)
        let node = try #require(grouped.selection.first)
        let ungrouped = try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry)
        try document.perform(ungrouped.command)
        let names = nodesNamed(in: document.graph.drawings)
        #expect(names.count == 1)
        #expect(names.isDisjoint(with: [GroupScopes.identity([node, scene.a1.id])]))
        #expect(ungrouped.selection.isSuperset(of: names), "the spliced node is the one the pick names now")
    }

    @Test func makeUniqueRenames() throws {
        let document = document(drawingOn: scene.a1.id)
        let grouped = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        try document.perform(grouped.command)
        let node = try #require(grouped.selection.first)
        let before = nodesNamed(in: document.graph.drawings)
        let unique = try GroupCommands.makeUnique(node, in: .root, of: document.content, registry: testRegistry)
        try document.perform(unique.command)
        let after = nodesNamed(in: document.graph.drawings)
        #expect(after.count == 1)
        #expect(after != before, "the copy's definition names its faces under new identities")
    }

    @Test func undoRestoresTheOldNames() throws {
        let document = document(drawingOn: scene.a1.id)
        let before = document.graph.drawings
        let edit = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        #expect(document.graph.drawings != before)
        document.undo()
        #expect(document.graph.drawings == before)
    }

    @Test func unrelatedDrawingsAreUntouched() throws {
        let unrelated = NodeID()
        let document = document(drawingOn: unrelated)
        let edit = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        #expect(!containsSetDrawings(edit.command))
        try document.perform(edit.command)
        #expect(nodesNamed(in: document.graph.drawings) == [unrelated])
        let none = self.document(drawingOn: nil)
        let plain = try GroupCommands.group([scene.a1.id], in: .root, of: none.content, registry: testRegistry)
        #expect(!containsSetDrawings(plain.command))
    }

    func containsSetDrawings(_ command: GraphCommand) -> Bool {
        switch command {
        case .setDrawings: true
        case .batch(let all): all.contains(where: containsSetDrawings)
        default: false
        }
    }

    @Test func constantValuePicksStillRename() {
        let a = NodeID(), b = NodeID()
        let pick = edgePick(a)
        let renamed = ConstantValue.edgePicks([pick]).renamingTags([a: b])
        #expect(renamed == .edgePicks([edgePick(b)]))
        let face = ConstantValue.facePick(facePick(a)).renamingTags([a: b])
        #expect(face == .facePick(facePick(b)))
    }
}
