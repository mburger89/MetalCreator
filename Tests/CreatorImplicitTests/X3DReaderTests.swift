import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

@Suite struct X3DReaderTests {
    private static func read(_ text: String, limit: Int = 10_000_000) throws -> ImportedModelMesh {
        try X3DReader.read(Data(text.utf8), triangleLimit: limit, isCancelled: { false })
    }

    private static func wrap(_ body: String, prefix: String = "") -> String {
        let tag = prefix.isEmpty ? "" : prefix + ":"
        return "<?xml version=\"1.0\"?><\(tag)X3D version=\"3.3\"><\(tag)Scene>\(body)</\(tag)Scene></\(tag)X3D>"
    }

    private static let faceSet = """
    <Shape><IndexedFaceSet coordIndex="0 1 2 -1"><Coordinate point="0 0 0, 1 0 0, 0 1 0"/></IndexedFaceSet></Shape>
    """

    private static func corners(_ mesh: TriangleMesh) -> [SIMD3<Float>] { mesh.triangles.map { mesh.positions[Int($0)] } }

    private static func problem(_ text: String, limit: Int = 10_000_000) -> String? {
        do { _ = try read(text, limit: limit) } catch let error as MeshImportProblem { return error.message } catch { return "\(error)" }
        return nil
    }

    @Test func triangleSet() throws {
        let text = Self.wrap("""
        <Shape><IndexedTriangleSet index="0 1 2 0 2 3"><Coordinate point="0 0 0 1 0 0 1 1 0 0 1 0"/></IndexedTriangleSet></Shape>
        """)
        let result = try Self.read(text)
        #expect(Self.corners(result.mesh) == [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 0, 0], [1, 1, 0], [0, 1, 0]])
        #expect(!result.isMillimetres && !result.skippedGeometry)
    }

    @Test func faceSetQuadAndClockwise() throws {
        let quad = """
        <Shape><IndexedFaceSet coordIndex="0,1,2,3,-1"><Coordinate point="0 0 0 1 0 0 1 1 0 0 1 0"/></IndexedFaceSet></Shape>
        """
        #expect(try Self.read(Self.wrap(quad)).mesh.triangles.count == 6)
        let flipped = Self.wrap(Self.faceSet.replacingOccurrences(of: "<IndexedFaceSet ", with: "<IndexedFaceSet ccw=\"false\" "))
        #expect(Self.corners(try Self.read(flipped).mesh) == [[0, 0, 0], [0, 1, 0], [1, 0, 0]])
    }

    @Test func transform() throws {
        let text = Self.wrap("<Transform translation=\"10 0 0\" rotation=\"0 0 1 1.5707963267949\">\(Self.faceSet)</Transform>")
        let c = Self.corners(try Self.read(text).mesh)
        let expected: [SIMD3<Float>] = [[10, 0, 0], [10, 1, 0], [9, 0, 0]]
        #expect(zip(c, expected).allSatisfy { abs($0.x - $1.x) < 1e-5 && abs($0.y - $1.y) < 1e-5 })
    }

    @Test func defAndUse() throws {
        let text = Self.wrap("""
        <Transform DEF="a">\(Self.faceSet.replacingOccurrences(of: "<Shape>", with: "<Shape DEF=\"s\">"))</Transform>
        <Transform translation="5 0 0"><Shape USE="s"/></Transform>
        """)
        let mesh = try Self.read(text).mesh
        #expect(mesh.triangles.count == 6)
        #expect(Self.corners(mesh).contains([5, 0, 0]))
    }

    @Test func sharedCoordinate() throws {
        let text = Self.wrap("""
        <Shape><IndexedFaceSet coordIndex="0 1 2 -1"><Coordinate DEF="c" point="0 0 0 1 0 0 0 1 0"/></IndexedFaceSet></Shape>
        <Shape><IndexedFaceSet coordIndex="2 1 0 -1"><Coordinate USE="c"/></IndexedFaceSet></Shape>
        """)
        #expect(try Self.read(text).mesh.triangles.count == 6)
    }

    @Test func namespacedElements() throws {
        let text = Self.wrap("<x3d:Shape><x3d:IndexedFaceSet coordIndex=\"0 1 2 -1\"><x3d:Coordinate point=\"0 0 0 1 0 0 0 1 0\"/>"
                             + "</x3d:IndexedFaceSet></x3d:Shape>", prefix: "x3d")
        #expect(try Self.read(text).mesh.triangles.count == 3)
    }

    @Test func boxAndSkippedGeometry() throws {
        let box = try Self.read(Self.wrap("<Shape><Box size=\"1 2 3\"/></Shape>")).mesh
        #expect(box.triangles.count == 36)
        let sphere = try Self.read(Self.wrap("<Shape><Sphere/></Shape>\(Self.faceSet)"))
        #expect(sphere.skippedGeometry && sphere.mesh.triangles.count == 3)
        #expect(Self.problem(Self.wrap("<Shape><Sphere/></Shape>")) == nil)
    }

    @Test func switchChoosesAndIgnoredElementsCount() throws {
        let text = Self.wrap("<Switch whichChoice=\"1\"><Metadata/>\(Self.faceSet)</Switch>")
        let result = try Self.read(text)
        #expect(result.mesh.triangles.count == 3 && !result.skippedGeometry)
        #expect(Self.problem(Self.wrap("<Switch>\(Self.faceSet)</Switch>")) == "This file holds no triangles.")
    }

    @Test func refusals() {
        #expect(Self.problem(Self.wrap("<Shape USE=\"nope\"/>")) == "This X3D file uses a shape before it is defined.")
        #expect(Self.problem(Self.wrap(Self.faceSet.replacingOccurrences(of: "0 1 2 -1", with: "0 1 7 -1")))
            == "This X3D file has a face that names a point it doesn't have.")
        #expect(Self.problem(Self.wrap(Self.faceSet.replacingOccurrences(of: "1 0 0", with: "1 x 0")))
            == "This X3D file has a bad number.")
        #expect(Self.problem("<!DOCTYPE x><X3D/>")?.contains("DOCTYPE") == true)
        #expect(Self.problem("<html/>") == "This file isn't an X3D file.")
        #expect(Self.problem(String(repeating: "<Group>", count: 300) + String(repeating: "</Group>", count: 300)) != nil)
        let short = "<Shape><IndexedTriangleSet index=\"0 1\"><Coordinate point=\"0 0 0\"/></IndexedTriangleSet></Shape>"
        #expect(Self.problem(Self.wrap(short)) == "This file holds no triangles.")
        #expect(Self.problem(Self.wrap(Self.faceSet), limit: 0) == MeshImportProblem.overTriangleLimit.message)
    }

    @Test func deepNestingEvaluatesWithoutRecursing() {
        let depth = 250
        let text = "<X3D>" + String(repeating: "<Group>", count: depth) + Self.faceSet + String(repeating: "</Group>", count: depth)
            + "</X3D>"
        #expect(Self.problem(text) == nil)
    }

    @Test func useCannotDoubleWithoutBound() {
        var body = "<Group DEF=\"g0\">\(Self.faceSet)</Group>"
        for level in 1..<40 { body += "<Group DEF=\"g\(level)\"><Group USE=\"g\(level - 1)\"/><Group USE=\"g\(level - 1)\"/></Group>" }
        #expect(Self.problem(Self.wrap(body)) == "This X3D file is too complex.")
    }

    @Test func cancellationIsHonoured() {
        let points = (0..<70_000).map { "\($0) 0 0" }.joined(separator: " ")
        let text = Self.wrap("<Shape><IndexedFaceSet coordIndex=\"0 1 2 -1\"><Coordinate point=\"\(points)\"/></IndexedFaceSet></Shape>")
        #expect(throws: CancellationError.self) { try X3DReader.read(Data(text.utf8), isCancelled: { true }) }
    }

    private static func set(_ points: String, _ index: String) -> String {
        "<Shape><IndexedFaceSet coordIndex=\"\(index)\"><Coordinate point=\"\(points)\"/></IndexedFaceSet></Shape>"
    }

    @Test func entitiesAndScientificNotationInLists() throws {
        let text = Self.wrap(Self.set("0&#32;0 0, 1e0 0 0, 0 1E0 +0.0", "0&#x20;1 2 -1"))
        #expect(try Self.read(text).mesh.triangles.count == 3)
        #expect(Self.problem(Self.wrap(Self.set("0 0 0 1 0 0 0 1 0", "0 1 2 -1").replacingOccurrences(of: "-1\"", with: "&bogus;\"")))
            != nil)
    }

    @Test func switchOutOfRangeAndNegative() {
        for choice in ["5", "-1", "2"] {
            let text = Self.wrap("<Switch whichChoice=\"\(choice)\">\(Self.faceSet)</Switch>")
            #expect(Self.problem(text) == "This file holds no triangles.")
        }
    }

    @Test func lodTakesTheFirstReadableChild() throws {
        let inline = "<Inline url=\"a.x3d\"/>"
        let result = try Self.read(Self.wrap("<LOD>\(inline)\(Self.faceSet)\(Self.faceSet)</LOD>"))
        #expect(result.mesh.triangles.count == 3)
    }

    @Test func coordinateDoubleAndOrderOfAttributes() throws {
        let text = Self.wrap("""
        <Shape><IndexedFaceSet coordIndex="0 1 2 -1"><CoordinateDouble point="0 0 0 1 0 0 0 1 0"/></IndexedFaceSet></Shape>
        """)
        #expect(try Self.read(text).mesh.triangles.count == 3)
        let late = Self.wrap("<Shape><IndexedFaceSet><Coordinate point=\"0 0 0 1 0 0 0 1 0\"/></IndexedFaceSet></Shape>")
        #expect(Self.problem(late) == "This file holds no triangles.")
    }

    @Test func shortRotationIsIgnored() throws {
        let text = Self.wrap("<Transform rotation=\"0 0 1\" translation=\"1 0 0\">\(Self.faceSet)</Transform>")
        #expect(Self.corners(try Self.read(text).mesh) == [[1, 0, 0], [2, 0, 0], [1, 1, 0]])
    }

    @Test func elementCapAndOversizeMessage() throws {
        let text = Data(Self.wrap(Self.faceSet).utf8)
        #expect(throws: MeshImportProblem.x3d("This X3D file is too complex.")) {
            try X3DReader.read(text, triangleLimit: 100, elementLimit: 3, isCancelled: { false })
        }
        let huge = Data(count: VRMLReader.maximumBytes + 1)
        #expect(throws: MeshImportProblem.x3d("This X3D file is larger than the 64 MB limit.")) {
            try X3DReader.read(huge, isCancelled: { false })
        }
    }

    @Test func prefixedAttributesAndStrayAttributes() throws {
        let text = Self.wrap("""
        <Group size="not a number"><Shape x3d:DEF="s"><IndexedFaceSet coordIndex="0 1 2 -1"><Coordinate point="0 0 0 1 0 0 0 1 0"/>
        </IndexedFaceSet></Shape><Shape USE="s"/></Group>
        """)
        #expect(try Self.read(text).mesh.triangles.count == 6)
    }

    @Test func leftoverTriangleIndicesAndTrailingElements() throws {
        let text = Self.wrap("<Shape><IndexedTriangleSet index=\"0 1 2 0 1\"><Coordinate point=\"0 0 0 1 0 0 0 1 0\"/>"
                             + "</IndexedTriangleSet></Shape>") + "<Trailing/>"
        #expect(try Self.read(text).mesh.triangles.count == 3)
    }

    @Test func randomMutationsNeverTrap() {
        let seed = Self.wrap("""
        <Transform translation="1 2 3" rotation="0 0 1 1.5" scale="1 1 1"><Shape DEF="S"><Appearance><Material/></Appearance>
        <IndexedFaceSet ccw="true" coordIndex="0 1 2 3 -1"><Coordinate point="0 0 0, 1 0 0, 1 1 0, 0 1 0"/></IndexedFaceSet></Shape>
        <Switch whichChoice="0"><Shape USE="S"/></Switch><Shape><Box size="1 2 3"/></Shape></Transform>
        """)
        let original = Array(seed.utf8)
        let specials = Array("<>/=\"' -.eE0123456789,:&;!?DEFUS".utf8)
        var random = SeededRandom(seed: 11)
        for _ in 0..<2_000 {
            var bytes = original
            for _ in 0..<(1 + Int(random.next() % 4)) where !bytes.isEmpty {
                let at = Int(random.next() % UInt64(bytes.count))
                switch random.next() % 3 {
                case 0: bytes[at] = specials[Int(random.next() % UInt64(specials.count))]
                case 1: bytes.remove(at: at)
                default: bytes.insert(specials[Int(random.next() % UInt64(specials.count))], at: at)
                }
            }
            _ = try? X3DReader.read(Data(bytes), triangleLimit: 1_000, isCancelled: { false })
        }
    }
}
