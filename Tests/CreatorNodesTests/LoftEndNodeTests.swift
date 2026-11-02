import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// The Loft node's end conditions (loft end conditions spec, Behaviour): settings, migration, messages, picks and the inspector.
struct LoftEndNodeTests {
    /// A 20 × 20 × 10 box, a Loft after it with one 12 × 12 section at z = 20, and the loft's pick of the box's top.
    struct Rig {
        var h = Harness()
        var box: Node
        var loft: Node

        init(wired: Bool = true, picked: Bool = true) {
            box = h.box(20, 20, 10)
            let rectangle = h.add(RectangleNode.self, ["width": .number(12), "height": .number(12),
                                                       "plane": .plane(.through(Vector3(0, 0, 20))),
        ])
            loft = h.add(LoftNode.self)
            h.wire(rectangle, "profile", to: loft, "sections")
            if wired { h.wire(box, "solid", to: loft, "solid") }
            if picked { h.set(loft, NodeSetting.startFace, .facePick(Rig.topPick(of: box))) }
        }

        static func topPick(of box: Node) -> FacePick { FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)]) }
    }

    // MARK: Settings and sockets

    @Test func theNodeIsVersion2WithTheEndSockets() {
        #expect(LoftNode.typeVersion == 2)
        let byName = Dictionary(uniqueKeysWithValues: LoftNode.inputs.map { ($0.name, $0) })
        #expect(byName["solid"]?.type == .solid && byName["solid"]?.isOptional == true)
        for name: SocketName in ["startContinuity", "endContinuity"] {
            #expect(byName[name]?.type == .integer && byName[name]?.defaultValue == .integer(0))
        }
        for name: SocketName in ["startWeight", "endWeight"] {
            #expect(byName[name]?.type == .number && byName[name]?.defaultValue == .number(1) && byName[name]?.range == 0.1...2)
        }
        #expect(LoftEndSetup.continuityOptions == ["Free", "Tangent (G1)", "Curvature (G2)"])
    }

    @Test func theFaceSettingsAreReservedAndSeededNowhere() {
        #expect(NodeSetting.all.isSuperset(of: [NodeSetting.startFace, NodeSetting.endFace]))
        #expect(NodeSetting.reservedForSockets.isSuperset(of: [NodeSetting.startFace, NodeSetting.endFace]))
        #expect(LoftNode.defaultSettings.isEmpty)
        #expect(BuiltInNodes.registry.makeNode(LoftNode.typeID).inputValues[NodeSetting.startFace] == nil)
    }

    // MARK: Migration (Review Focus 1)

    @Test func migratingFromVersion1StoresNothing() {
        var old = BuiltInNodes.registry.makeNode(LoftNode.typeID)
        old.typeVersion = 1
        old.inputValues = ["ruled": .bool(true)]
        #expect(LoftNode.migrate(old, from: 1) == old)
    }

    #if canImport(CreatorOCCT)
    @Test func aLoftWithNoFaceBuildsExactlyWhatTheKernelsPlainLoftBuilds() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let sizes = h.add(SeriesNode.self, ["start": .number(20), "step": .number(-8), "count": .integer(2)])
        let heights = h.add(SeriesNode.self, ["start": .number(0), "step": .number(20), "count": .integer(2)])
        let plane = h.add(PlaneNode.self)
        h.wire(heights, "values", to: plane, "offset")
        let square = h.add(RectangleNode.self)
        h.wire(sizes, "values", to: square, "width")
        h.wire(sizes, "values", to: square, "height")
        h.wire(plane, "plane", to: square, "plane")
        let loft = h.add(LoftNode.self)
        h.wire(square, "profile", to: loft, "sections")
        let built = try onlySolid(try await h.run([loft], kernel: kernel), loft)
        let sections = [Profile2D.rectangle(width: 20, height: 20, plane: .xy),
                        Profile2D.rectangle(width: 12, height: 12, plane: Plane.xy.offset(by: 20)),
        ]
        let direct = try await kernel.loft(sections, ruled: false, tag: NodeTag(node: NodeID(), item: 0))
        #expect(isClose(try await volume(built, kernel), try await volume(direct, kernel), relative: 1e-9))
        #expect(built.topology.faces.count == direct.topology.faces.count)
    }
    #endif

    // MARK: Messages

    @Test func aFaceWithNoPartSaysSo() async throws {
        var rig = Rig(wired: false)
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == "Pick a face of the part for the loft's start.")
        rig.h.set(rig.loft, NodeSetting.startFace, nil)
        rig.h.set(rig.loft, NodeSetting.endFace, .facePick(Rig.topPick(of: rig.box)))
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == "Pick a face of the part for the loft's end.")
    }

    @Test func aSingleSectionNeedsAFaceToMakeTwo() async throws {
        let rig = Rig(picked: false)
        let message = try #require(try await rig.h.run([rig.loft]).error(rig.loft))
        #expect(message.contains("at least two sections"))
    }

    @Test func aStaleOrUnreadablePickIsAPlainError() async throws {
        var rig = Rig()
        rig.h.set(rig.loft, NodeSetting.startFace, .text("top"))
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == "The loft's start face can't be read. Pick the face again.")
        rig.h.set(rig.loft, NodeSetting.startFace, .facePick(FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])))
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == "The loft's start face isn't on this part any more. Pick it again.")
    }

    @Test func straightSidesRefuseEndConditions() async throws {
        var rig = Rig()
        rig.h.set(rig.loft, "ruled", .bool(true))
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == "Straight sides can't have end conditions.")
    }

    @Test func aFakeKernelRefusesAFaceEndInWords() async throws {
        let rig = Rig()
        #expect(try await rig.h.run([rig.loft]).error(rig.loft) == KernelError.unsupported("loft end conditions").userMessage)
    }

    // MARK: The inspector

    @Test func continuityShowsOnlyForAnEndWithAFaceAndWeightOnlyForTangentAndCurvature() {
        func controls(_ node: Node) -> [InspectorControl] { LoftNode.inspector(for: node).flatMap(\.controls) }
        func name(of control: InspectorControl) -> SocketName? {
            switch control {
            case .segmented(let name, _), .slider(let name): name
            default: nil
            }
        }
        func has(_ node: Node, _ socket: SocketName) -> Bool { controls(node).contains(where: { name(of: $0) == socket }) }

        var loft = BuiltInNodes.registry.makeNode(LoftNode.typeID)
        #expect(!has(loft, "startContinuity") && !has(loft, "endContinuity") && !has(loft, "startWeight"))
        let titles = controls(loft).compactMap { control -> String? in if case .button(let title, _) = control { title } else { nil } }
        #expect(titles == ["Pick Start Face in View…", "Pick End Face in View…"])

        loft.inputValues[NodeSetting.startFace] = .facePick(FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)]))
        #expect(has(loft, "startContinuity") && !has(loft, "endContinuity"))
        #expect(!has(loft, "startWeight"), "Free has no weight")
        let clear = InspectorControl.button(title: "Clear Start Face", action: .clearLoftStartFace)
        #expect(controls(loft).contains(clear))

        for continuity in [1, 2] {
            loft.inputValues["startContinuity"] = .integer(continuity)
            #expect(has(loft, "startWeight") && !has(loft, "endWeight"))
        }
        loft.inputValues[NodeSetting.endFace] = loft.inputValues[NodeSetting.startFace]
        #expect(has(loft, "endContinuity") && !has(loft, "endWeight"))
        let segmented = InspectorControl.segmented("startContinuity", options: ["Free", "Tangent (G1)", "Curvature (G2)"])
        #expect(controls(loft).contains(segmented))
    }

    // MARK: Pick resolution on OCCT (Review Focus 5)

    #if canImport(CreatorOCCT)
    /// Two overlapping 20 × 10 × 6 boxes unioned, so their tops are one merged face, picked; then the second box moves away.
    @Test func aPickOnAFaceThatMergedAwayWarnsAndNeverTakesANeighbour() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let first = h.box(20, 10, 6)
        let secondRectangle = h.add(RectangleNode.self, ["width": .number(20), "height": .number(10),
                                                         "plane": .plane(.through(Vector3(10, 0, 0))),
        ])
        let second = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(secondRectangle, "profile", to: second, "profile")
        let union = h.add(BooleanNode.self)
        h.wire(first, "solid", to: union, "target")
        h.wire(second, "solid", to: union, "tools")
        let merged = try onlySolid(try await h.run([union], kernel: kernel), union)
        let top = try #require(merged.topology.faces.first { $0.normal == Vector3(0, 0, 1) })
        #expect(top.tags.count > 1, "the union merged the tops")
        let pick = try #require(merged.topology.facePick(for: top.id))

        let rectangle = h.add(RectangleNode.self, ["width": .number(12), "height": .number(6),
                                                   "plane": .plane(.through(Vector3(0, 0, 16))),
        ])
        let loft = h.add(LoftNode.self, [NodeSetting.startFace: .facePick(pick)])
        h.wire(rectangle, "profile", to: loft, "sections")
        h.wire(union, "solid", to: loft, "solid")
        #expect(try await h.run([loft], kernel: kernel).error(loft) == nil)

        // The faces come apart: the pick is ambiguous, says so and still builds on one of the two tops, not on a side.
        h.set(secondRectangle, "plane", .plane(.through(Vector3(60, 0, 0))))
        let apart = h
        let report = try await apart.run([loft], kernel: kernel)
        let warning = try #require(report.warning(loft))
        #expect(warning.contains("merged with a face from another part of the model that has since changed"))
        let built = try onlySolid(report, loft)
        #expect(built.topology.faces.count == 6)
    }

    /// Review Focus 5's other half: the picked face is gone altogether (the box is replaced by a cylinder's wall).
    @Test func aPickWhoseFaceIsGoneIsAnErrorNotAnotherFace() async throws {
        let kernel = OCCTKernel()
        var rig = Rig()
        rig.h.set(rig.loft, NodeSetting.startFace,
                  .facePick(FacePick(tags: [TopoTag(node: rig.box.id, item: 0, role: .side(segment: 9))])))
        #expect(try await rig.h.run([rig.loft], kernel: kernel).error(rig.loft)
            == "The loft's start face isn't on this part any more. Pick it again.")
    }
    #endif
}
