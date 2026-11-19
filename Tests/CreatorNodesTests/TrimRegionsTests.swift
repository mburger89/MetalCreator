import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorNodes

/// NS-4 Task 5: how Trim Surface's keep picks resolve against a split's pieces (R4, R17), over hand-built topologies.
struct TrimRegionsTests {
    let source = NodeID()
    let cutter = NodeID()

    var base: TopoTag { TopoTag(node: source, item: 0, role: .side(segment: 0)) }

    func side(_ side: CutSide, _ index: Int = 0) -> TopoTag {
        TopoTag(node: cutter, item: 0, role: .cutSide(.curve(index: index, piece: 0), side))
    }

    func face(_ id: Int, _ tags: Set<TopoTag>, at centroid: Vector3, area: Double = 10) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: .unitZ, area: area, centroid: centroid, tags: tags, isOnOpenShell: true)
    }

    func topology(_ faces: [FaceInfo]) -> Topology { Topology(faces: faces, edges: []) }

    /// A disk and the ring round it (one piece each).
    var diskAndRing: Topology {
        topology([face(0, [base, side(.inside)], at: .zero), face(1, [base, side(.outside)], at: Vector3(8, 0, 0))])
    }

    /// A band cut by a circle: two outside pieces that share one tag set.
    var band: Topology {
        topology([face(0, [base, side(.outside)], at: Vector3(-8, 0, 0)), face(1, [base, side(.outside)], at: Vector3(8, 0, 0))])
    }

    @Test func aSingleMatchIsKept() {
        let topology = diskAndRing
        let pick = RegionPick(pick: FacePick(tags: topology.faces[0].tags))
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces == [0])
        #expect(result.warnings.isEmpty)
    }

    @Test func aPickThatNamesTwoPiecesWarns() {
        let topology = band
        let pick = RegionPick(pick: FacePick(tags: topology.faces[0].tags, centroid: Vector3(7, 0, 0)), sharedBy: 1)
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces == [1])
        #expect(result.warnings == ["A picked region now names 2 pieces; Trim Surface kept the one nearest where it was picked."])
    }

    @Test func aPickSharedWhenMadeDoesNotWarn() {
        let topology = band
        let pick = RegionPick(pick: FacePick(tags: topology.faces[0].tags, centroid: Vector3(-7, 0, 0)), sharedBy: 2)
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces == [0])
        #expect(result.warnings.isEmpty)
    }

    @Test func aPickNamingMorePiecesThanWhenMadeWarns() {
        let topology = topology([face(0, [base, side(.outside)], at: Vector3(-8, 0, 0)),
                                 face(1, [base, side(.outside)], at: Vector3(0, 0, 0)),
                                 face(2, [base, side(.outside)], at: Vector3(8, 0, 0)),
        ])
        let pick = RegionPick(pick: FacePick(tags: topology.faces[0].tags, centroid: Vector3(7, 0, 0)), sharedBy: 2)
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0)], [FaceID(1)], [FaceID(2)]], in: topology)
        #expect(result.pieces == [2])
        #expect(result.warnings == ["A picked region now names 3 pieces; Trim Surface kept the one nearest where it was picked."])
    }

    @Test func aPickKeepsItsWholePiece() {
        let wall = TopoTag(node: source, item: 0, role: .side(segment: 1))
        let topology = topology([face(0, [base, side(.inside)], at: Vector3(-1, 0, 0)),
                                 face(1, [wall, side(.inside)], at: Vector3(1, 0, 0)),
                                 face(2, [base, side(.outside)], at: Vector3(9, 0, 0)),
        ])
        let pick = RegionPick(pick: FacePick(tags: [wall]))
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0), FaceID(1)], [FaceID(2)]], in: topology)
        #expect(result.pieces == [0])
        #expect(result.warnings.isEmpty)
    }

    @Test func twoPicksOfOnePieceKeepItOnce() {
        let wall = TopoTag(node: source, item: 0, role: .side(segment: 1))
        let topology = topology([face(0, [base, side(.inside)], at: Vector3(-1, 0, 0)),
                                 face(1, [wall, side(.inside)], at: Vector3(1, 0, 0)),
                                 face(2, [base, side(.outside)], at: Vector3(9, 0, 0)),
        ])
        let picks = [RegionPick(pick: FacePick(tags: [wall])), RegionPick(pick: FacePick(tags: topology.faces[0].tags))]
        let result = TrimRegions.resolve(picks, pieces: [[FaceID(0), FaceID(1)], [FaceID(2)]], in: topology)
        #expect(result.pieces == [0])
    }

    @Test func aVanishedPickWarns() {
        let topology = diskAndRing
        let gone = TopoTag(node: NodeID(), item: 0, role: .startCap)
        let picks = [RegionPick(pick: FacePick(tags: [gone])), RegionPick(pick: FacePick(tags: topology.faces[1].tags))]
        let result = TrimRegions.resolve(picks,
                                         pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces == [1])
        #expect(result.warnings == ["A picked region no longer exists; pick the regions again."])
    }

    @Test func noPicksMatchingIsARefusal() {
        let topology = diskAndRing
        let gone = TopoTag(node: NodeID(), item: 0, role: .startCap)
        let result = TrimRegions.resolve([RegionPick(pick: FacePick(tags: [gone]))], pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces.isEmpty)
        #expect(result.warnings == ["A picked region no longer exists; pick the regions again."])
    }

    @Test func aNarrowedPickIsKeptWithItsOwnWarning() {
        let topology = diskAndRing
        let other = TopoTag(node: NodeID(), item: 0, role: .startCap)
        let pick = RegionPick(pick: FacePick(tags: topology.faces[1].tags.union([other]), normal: .unitZ, centroid: Vector3(8, 0, 0)))
        let result = TrimRegions.resolve([pick], pieces: [[FaceID(0)], [FaceID(1)]], in: topology)
        #expect(result.pieces == [1])
        #expect(result.warnings == [TrimRegions.narrowedPick])
    }

    @Test func pickForPieceRecordsSharedBy() throws {
        let topology = diskAndRing
        let disk = try #require(TrimRegions.pick(forPiece: 0, pieces: [[FaceID(0)], [FaceID(1)]], in: topology))
        #expect(disk.sharedBy == 1)
        #expect(disk.pick.tags == topology.faces[0].tags)
        let bandPieces = [[FaceID(0)], [FaceID(1)]]
        let outside = try #require(TrimRegions.pick(forPiece: 1, pieces: bandPieces, in: band))
        #expect(outside.sharedBy == 2)
        #expect(outside.pick.centroid == Vector3(8, 0, 0))
        #expect(TrimRegions.pick(forPiece: 5, pieces: bandPieces, in: band) == nil)
    }
}
